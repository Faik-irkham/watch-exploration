package com.example.hr_07_ble_dasar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
 * sudah destroyed — selama proses/service ini sendiri tidak dibunuh
 * sistem (foreground service + notifikasi persisten membuatnya jauh
 * lebih tahan dibanding proses biasa).
 */

class HeartRateBleService : Service(), SensorEventListener {

  companion object {
    const val ACTION_START = "com.example.hr_07_ble_dasar.action.START"
    const val ACTION_STOP = "com.example.hr_07_ble_dasar.action.STOP"
    const val EXTRA_INTERVAL_MINUTES = "interval_minutes"

    private const val NOTIF_CHANNEL_ID = "heart_rate_channel"
    private const val NOTIF_ID = 888
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private lateinit var sensorManager: SensorManager
  private var heartRateSensor: Sensor? = null
  private lateinit var bleManager: BleGattServerManager
  private lateinit var dbHelper: HeartRateDbHelper

  private var intervalMinutes = 1
  private var isListeningToSensor = false
  private var isSessionActive = false

  private val periodicTick = object : Runnable {
    override fun run() {
      readOnce()
      mainHandler.postDelayed(this, intervalMinutes * 60_000L)
    }
  }

  override fun onCreate() {
    super.onCreate()
    sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
    heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)
    bleManager = BleGattServerManager(applicationContext)
    dbHelper = HeartRateDbHelper(applicationContext)
    ensureNotificationChannel()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        intervalMinutes = (intent.getIntExtra(EXTRA_INTERVAL_MINUTES, 1)).coerceAtLeast(1)
        startSession()
      }
      ACTION_STOP -> stopSession()
    }
    return START_STICKY
  }

  private fun startSession() {
    if(isSessionActive) return
    isSessionActive = true

    if(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIF_ID, buildNotification(), foregroundServiceType())
    } else {
      startForeground(NOTIF_ID, buildNotification())
    }

    if(!bleManager.start()) {
      // Error sudah dilaporkan lewat LiveUpdateBridge; pencatatan
      // sensor tetap dilanjutkan supaya data tidak hilang total.
    }

    if(heartRateSensor == null) {
      LiveUpdateBridge.emitSensorError("Sensor heart rate tidak tersedia di perangkat ini")
    }

    mainHandler.removeCallbacks(periodicTick)
    mainHandler.post(periodicTick)
  }

  private fun stopSession() {
    isSessionActive = false
    mainHandler.removeCallbacks(periodicTick)
    if(isListeningToSensor) {
      sensorManager.unregisterListener(this)
      isListeningToSensor = false
    }
    bleManager.stop()
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  private fun readOnce() {
    val sensor = heartRateSensor ?: return
    if(isListeningToSensor) return
    isListeningToSensor = sensorManager.registerListener(
      this, sensor, SensorManager.SENSOR_DELAY_NORMAL
    )
    if(!isListeningToSensor) {
      LiveUpdateBridge.emitSensorError ("Gagal mengaktifkan sensor. Pastikan izin Sensor tubuh diizinkan dan mode hemat daya mati.")
    }
  }

  override fun onSensorChanged(event: SensorEvent?) {
    if(event == null || event.sensor.type != Sensor.TYPE_HEART_RATE) return
    val bpm = event.values.firstOrNull() ?: return
    val accuracy = event.accuracy

    // Abaikan bacaan yang sensor sendiri tandai tidak bisa dipercaya
    // (accuracy 0) dan bacaan 0 bpm (sensor belum stabil).
    if (bpm <= 0f || accuracy <= 0) return

    // Cukup 1 bacaan valid per interval → lepas listener sekarang.
    sensorManager.unregisterListener(this)
    isListeningToSensor = false

    val now = System.currentTimeMillis()
    dbHelper.insertReading(bpm.toDouble(), accuracy, now)
    bleManager.updateBpm(bpm.toInt())
    LiveUpdateBridge.emitBpm(bpm.toDouble(), intervalMinutes)
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
      // Nilai accuracy sudah ikut dikirim tiap onSensorChanged.
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
      mainHandler.removeCallbacks(periodicTick)
      if (isListeningToSensor) sensorManager.unregisterListener(this)
      bleManager.stop()
      super.onDestroy()
  }
}