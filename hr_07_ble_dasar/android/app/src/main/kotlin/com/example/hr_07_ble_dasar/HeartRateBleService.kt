package com.example.hr_07_ble_dasar

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * Foreground Service NATIVE (murni Android, tanpa isolate Dart) yang jadi
 * satu-satunya sumber untuk:
 *  1. Membaca sensor detak jantung tiap interval (1 bacaan valid/interval).
 *  2. Menyimpan hasilnya ke SQLite (file sama dengan sqflite di Dart).
 *  3. Mengirim (notify) bpm terbaru ke GATT Server BLE.
 *  4. Melaporkan progres ke UI Flutter lewat LiveUpdateBridge KALAU ada
 *     yang sedang mendengarkan (opsional, cuma untuk tampilan).
 *
 * Karena ini Service Android biasa (bukan lewat channel yang terikat ke
 * suatu FlutterEngine/isolate tertentu), loop ini tetap jalan baik saat
 * app di foreground, diminimize, layar mati, ataupun Activity Flutter-nya
 * sudah destroyed.
 *
 * SOAL LAYAR MATI / DOZE:
 * Foreground service hanya menjaga PROSES tidak dibunuh - ia sama sekali
 * tidak menjaga CPU tetap bangun. Karena itu penjadwalan di sini memakai
 * tiga lapis pertahanan:
 *
 *  a. AlarmManager RTC_WAKEUP untuk detak interval. Basisnya jam dinding
 *     dan ia MEMBANGUNKAN CPU. Handler.postDelayed() yang dipakai versi
 *     sebelumnya tidak bisa keduanya: basisnya uptime (berhenti menghitung
 *     selama CPU suspend) dan tidak pernah membangunkan siapa pun, jadi
 *     interval melar tak menentu begitu layar mati.
 *  b. PARTIAL_WAKE_LOCK pendek selama jendela pembacaan. Wake lock bawaan
 *     alarm sudah dilepas begitu onStartCommand() selesai, padahal sensor
 *     baru memberi bacaan valid beberapa detik sesudahnya - tanpa lapisan
 *     ini, CPU keburu tidur lagi sebelum notify BLE sempat dikirim.
 *  c. Varian sensor wakeup kalau perangkat menyediakannya, supaya event
 *     sensor sendiri ikut mampu membangunkan CPU.
 *
 * Status sesi juga disimpan ke SharedPreferences, karena PendingIntent alarm
 * dipegang sistem dan HIDUP LEBIH LAMA daripada proses aplikasi: alarm bisa
 * tiba di proses yang baru dihidupkan lagi setelah service sempat dibunuh.
 */

class HeartRateBleService : Service(), SensorEventListener {

  companion object {
    const val ACTION_START = "com.example.hr_07_ble_dasar.action.START"
    const val ACTION_STOP = "com.example.hr_07_ble_dasar.action.STOP"
    const val ACTION_TICK = "com.example.hr_07_ble_dasar.action.TICK"
    const val EXTRA_INTERVAL_MINUTES = "interval_minutes"

    private const val TAG = "HR_SERVICE"
    private const val NOTIF_CHANNEL_ID = "heart_rate_channel"
    private const val NOTIF_ID = 888

    private const val ALARM_REQUEST_CODE = 1001
    private const val WAKE_LOCK_TAG = "hr_07_ble_dasar::SensorRead"
    /** Kelebihan umur wake lock di atas jendela sensor, untuk menutup
     *  waktu tulis SQLite + notify BLE sesudah bacaan didapat. */
    private const val WAKE_LOCK_SLACK_MS = 10_000L

    private const val PREFS_NAME = "heart_rate_session"
    private const val KEY_ACTIVE = "session_active"
    private const val KEY_INTERVAL = "session_interval"
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private lateinit var sensorManager: SensorManager
  private lateinit var alarmManager: AlarmManager
  private var heartRateSensor: Sensor? = null
  private lateinit var bleManager: BleGattServerManager
  private lateinit var dbHelper: HeartRateDbHelper
  private var wakeLock: PowerManager.WakeLock? = null

  private val prefs by lazy { getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

  private var intervalMinutes = 1
  private var isListeningToSensor = false
  private var isSessionActive = false

  /**
   * Batas waktu menunggu SATU bacaan valid dalam satu interval. Sensor
   * detak jantung sering mengembalikan accuracy 0 saat jam masih longgar
   * atau baru dipakai; kalau ditunggu tanpa batas, listener-nya nyangkut
   * sampai interval berikutnya sehingga interval itu ikut kosong (dan
   * baterai terkuras). Lewat batas ini sensor dilepas dan interval
   * tersebut dinyatakan gagal secara eksplisit.
   */
  private fun sensorWindowMs(): Long =
    minOf(30_000L, intervalMinutes * 60_000L / 2)

  private val sensorTimeout = Runnable {
    if (isListeningToSensor) {
      sensorManager.unregisterListener(this)
      isListeningToSensor = false
      LiveUpdateBridge.emitSensorError(
        "Tidak dapat bacaan valid dalam ${sensorWindowMs() / 1000} detik. " +
        "Interval ini dilewati - pastikan jam menempel pas di pergelangan."
      )
    }
    // Interval ini selesai (gagal), CPU boleh tidur lagi.
    releaseWakeLock()
  }

  override fun onCreate() {
    super.onCreate()
    sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
    alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

    // Varian wakeup dipakai kalau perangkat menyediakannya: event-nya sendiri
    // yang membangunkan CPU, jadi bacaan tetap sampai walau wake lock kita
    // kebetulan sudah lepas. Tidak semua jam punya, karena itu ada fallback
    // ke sensor non-wakeup.
    heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE, true)
      ?: sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)

    wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
      .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
      // Tanpa reference counting, acquire/release jadi idempoten sehingga
      // release ganda tidak melempar exception.
      .apply { setReferenceCounted(false) }

    bleManager = BleGattServerManager(applicationContext)
    dbHelper = HeartRateDbHelper(applicationContext)
    ensureNotificationChannel()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        intervalMinutes = (intent.getIntExtra(EXTRA_INTERVAL_MINUTES, 1)).coerceAtLeast(1)
        saveSession(true)
        startSession()
      }

      ACTION_STOP -> {
        saveSession(false)
        stopSession()
        return START_NOT_STICKY
      }

      ACTION_TICK -> {
        when {
          isSessionActive -> {
            // Alarm datang lewat getForegroundService(), jadi janji
            // startForeground() dipenuhi lagi. Service yang sudah foreground
            // hanya memperbarui notifikasinya - murah, dan menutup celah
            // kalau state foreground sempat hilang di sisi sistem.
            startForegroundCompat()
            scheduleNextTick()
            readOnce()
          }
          // Alarm tiba di proses yang baru dihidupkan lagi setelah service
          // sempat dibunuh sistem: sesi dipulihkan dari SharedPreferences.
          // startSession() sekaligus menjadwalkan tick berikutnya + membaca.
          hasSavedSession() -> {
            intervalMinutes = savedInterval()
            Log.d(TAG, "Sesi dipulihkan dari alarm, interval $intervalMinutes menit")
            startSession()
          }
          else -> {
            abortWithoutSession()
            return START_NOT_STICKY
          }
        }
      }

      // Intent null / action tak dikenal: biasanya service dihidupkan ulang
      // sistem setelah dibunuh karena tekanan memori.
      else -> {
        if (hasSavedSession()) {
          intervalMinutes = savedInterval()
          startSession()
        } else {
          abortWithoutSession()
          return START_NOT_STICKY
        }
      }
    }
    return START_REDELIVER_INTENT
  }

  private fun startSession() {
    if(isSessionActive) return
    isSessionActive = true

    startForegroundCompat()

    if(!bleManager.start()) {
      // Error sudah dilaporkan lewat LiveUpdateBridge; pencatatan
      // sensor tetap dilanjutkan supaya data tidak hilang total.
    }

    if(heartRateSensor == null) {
      LiveUpdateBridge.emitSensorError("Sensor heart rate tidak tersedia di perangkat ini")
    }

    // Jadwalkan tick berikutnya DULU supaya jarak antar interval tetap
    // presisi, tidak ikut molor mengikuti lamanya sensor menyala.
    scheduleNextTick()
    readOnce()
  }

  private fun stopSession() {
    isSessionActive = false
    cancelTick()
    mainHandler.removeCallbacks(sensorTimeout)
    if(isListeningToSensor) {
      sensorManager.unregisterListener(this)
      isListeningToSensor = false
    }
    releaseWakeLock()
    bleManager.stop()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  /**
   * Jalur keluar untuk kondisi "dinyalakan tapi tidak ada sesi". Service
   * bisa saja tiba lewat getForegroundService(), dan janji startForeground()
   * tetap wajib dipenuhi lebih dulu - kalau tidak, sistem melempar
   * ForegroundServiceDidNotStartInTimeException.
   */
  private fun abortWithoutSession() {
    startForegroundCompat()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  // ---------------------------------------------------------------------
  // Penjadwalan interval (AlarmManager)
  // ---------------------------------------------------------------------

  private fun tickPendingIntent(): PendingIntent {
    val intent = Intent(this, HeartRateBleService::class.java).apply {
      action = ACTION_TICK
    }
    // getForegroundService(), bukan getService(): saat alarm berbunyi app
    // sedang di background, dan hanya varian ini yang boleh menyalakan
    // foreground service dari sana.
    return PendingIntent.getForegroundService(
      this, ALARM_REQUEST_CODE, intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
  }

  private fun scheduleNextTick() {
    val triggerAt = System.currentTimeMillis() + intervalMinutes * 60_000L
    val pending = tickPendingIntent()

    val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        alarmManager.canScheduleExactAlarms()

    try {
      if (canExact) {
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
      } else {
        // Tanpa izin exact alarm, ini tetap menembus Doze - hanya waktunya
        // boleh digeser sistem. Jauh lebih baik daripada tidak jalan sama sekali.
        Log.w(TAG, "Izin exact alarm tidak ada, memakai alarm inexact.")
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
      }
    } catch (e: SecurityException) {
      Log.w(TAG, "Exact alarm ditolak sistem, jatuh ke inexact: ${e.message}")
      alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
    }
  }

  private fun cancelTick() {
    alarmManager.cancel(tickPendingIntent())
  }

  // ---------------------------------------------------------------------
  // Wake lock
  // ---------------------------------------------------------------------

  private fun acquireWakeLock() {
    try {
      // Timeout dipasang sebagai pengaman: kalau ada satu jalur keluar yang
      // terlewat melepas, wake lock tetap gugur sendiri dan baterai aman.
      wakeLock?.acquire(sensorWindowMs() + WAKE_LOCK_SLACK_MS)
    } catch (e: Exception) {
      Log.w(TAG, "Gagal acquire wake lock: ${e.message}")
    }
  }

  private fun releaseWakeLock() {
    val lock = wakeLock ?: return
    try {
      if (lock.isHeld) lock.release()
    } catch (e: Exception) {
      Log.w(TAG, "Gagal release wake lock: ${e.message}")
    }
  }

  // ---------------------------------------------------------------------
  // Status sesi (bertahan melewati kematian proses)
  // ---------------------------------------------------------------------

  private fun saveSession(active: Boolean) {
    prefs.edit()
      .putBoolean(KEY_ACTIVE, active)
      .putInt(KEY_INTERVAL, intervalMinutes)
      .apply()
  }

  private fun hasSavedSession(): Boolean = prefs.getBoolean(KEY_ACTIVE, false)

  private fun savedInterval(): Int = prefs.getInt(KEY_INTERVAL, 1).coerceAtLeast(1)

  // ---------------------------------------------------------------------
  // Pembacaan sensor
  // ---------------------------------------------------------------------

  private fun readOnce() {
    val sensor = heartRateSensor ?: return
    // Sisa listener dari interval sebelumnya dibersihkan dulu, supaya satu
    // interval tidak pernah "kehilangan giliran" gara-gara nyangkut.
    if(isListeningToSensor) {
      mainHandler.removeCallbacks(sensorTimeout)
      sensorManager.unregisterListener(this)
      isListeningToSensor = false
    }

    // Dipegang SEBELUM registerListener dan baru dilepas setelah notify BLE
    // terkirim, supaya CPU tidak tidur di tengah jendela pembacaan.
    acquireWakeLock()

    isListeningToSensor = sensorManager.registerListener(
      this, sensor, SensorManager.SENSOR_DELAY_NORMAL
    )
    if(!isListeningToSensor) {
      releaseWakeLock()
      LiveUpdateBridge.emitSensorError ("Gagal mengaktifkan sensor. Pastikan izin Sensor tubuh diizinkan dan mode hemat daya mati.")
      return
    }
    mainHandler.postDelayed(sensorTimeout, sensorWindowMs())
  }

  override fun onSensorChanged(event: SensorEvent?) {
    if(event == null || event.sensor.type != Sensor.TYPE_HEART_RATE) return
    val bpm = event.values.firstOrNull() ?: return
    val accuracy = event.accuracy

    // Abaikan bacaan yang sensor sendiri tandai tidak bisa dipercaya
    // (accuracy 0) dan bacaan 0 bpm (sensor belum stabil).
    if (bpm <= 0f || accuracy <= 0) return

    // Cukup 1 bacaan valid per interval → lepas listener sekarang.
    mainHandler.removeCallbacks(sensorTimeout)
    sensorManager.unregisterListener(this)
    isListeningToSensor = false

    val now = System.currentTimeMillis()
    dbHelper.insertReading(bpm.toDouble(), accuracy, now)
    // Satu-satunya titik pengiriman BLE: tepat 1 notify per interval.
    val sent = bleManager.updateBpm(bpm.toInt())
    LiveUpdateBridge.emitBpm(bpm.toDouble(), intervalMinutes)
    if (!sent) {
      LiveUpdateBridge.emitBleStatus(
        "broadcasting",
        "Belum ada phone yang subscribe. Bacaan disimpan di jam saja."
      )
    }

    // Dilepas paling akhir - setelah SQLite ditulis DAN notify BLE dikirim.
    releaseWakeLock()
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
      // Nilai accuracy sudah ikut dikirim tiap onSensorChanged.
  }

  // ---------------------------------------------------------------------
  // Foreground / notifikasi
  // ---------------------------------------------------------------------

  private fun startForegroundCompat() {
    if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIF_ID, buildNotification(), foregroundServiceType())
    } else {
      startForeground(NOTIF_ID, buildNotification())
    }
  }

  private fun buildNotification(): Notification {
    return Notification.Builder(this, NOTIF_CHANNEL_ID)
        .setContentTitle("Sensor Aktif")
        .setContentText("Memantau detak jantung tiap $intervalMinutes menit...")
        .setSmallIcon(android.R.drawable.ic_menu_myplaces)
        .setOngoing(true)
        .build()
  }

  private fun ensureNotificationChannel() {
    val manager = getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(
        NOTIF_CHANNEL_ID,
        "Pemantau Detak Jantung",
        NotificationManager.IMPORTANCE_LOW
    ).apply { description = "Menjalankan aplikasi agar tidak ditutup sistem" }
    manager.createNotificationChannel(channel)
  }

  private fun foregroundServiceType(): Int =
    ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onDestroy() {
      mainHandler.removeCallbacks(sensorTimeout)
      if (isListeningToSensor) {
        sensorManager.unregisterListener(this)
        isListeningToSensor = false
      }
      releaseWakeLock()
      bleManager.stop()
      // Alarm sengaja TIDAK dibatalkan di sini. Kalau service dibunuh sistem,
      // justru alarm itulah yang menghidupkannya kembali di interval
      // berikutnya lewat ACTION_TICK. Pembatalan hanya lewat stopSession().
      super.onDestroy()
  }
}
