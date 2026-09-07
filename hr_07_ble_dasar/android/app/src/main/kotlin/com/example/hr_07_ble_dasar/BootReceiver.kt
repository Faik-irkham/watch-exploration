package com.example.hr_07_ble_dasar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Menghidupkan kembali sesi pemantauan setelah jam dinyalakan ulang.
 *
 * Alarm `AlarmManager` TIDAK bertahan melewati reboot — seluruh alarm
 * terhapus saat perangkat mati. Tanpa receiver ini, `session_active` di
 * SharedPreferences tetap bernilai true sesudah reboot tetapi tidak ada
 * satu pun yang menjadwalkan tick berikutnya, sehingga sesi mati diam-diam
 * dan baru ketahuan saat pengguna membuka aplikasi.
 *
 * `BOOT_COMPLETED` adalah salah satu pengecualian resmi dari larangan
 * menyalakan foreground service dari background, jadi
 * `startForegroundService()` di sini sah dipanggil.
 *
 * MY_PACKAGE_REPLACED ikut ditangkap supaya sesi juga pulih setelah
 * aplikasi diperbarui — proses lama dimatikan saat pemasangan ulang, dan
 * alarmnya ikut hilang bersama dengannya.
 */
class BootReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG = "HR_BOOT"
    // Dipakai sebagian ROM (terutama perangkat HTC lama) sebagai pengganti
    // BOOT_COMPLETED saat fast boot. Murah untuk ikut didengarkan.
    private const val ACTION_QUICKBOOT = "android.intent.action.QUICKBOOT_POWERON"
  }

  override fun onReceive(context: Context, intent: Intent?) {
    val action = intent?.action ?: return
    if (action != Intent.ACTION_BOOT_COMPLETED &&
        action != Intent.ACTION_MY_PACKAGE_REPLACED &&
        action != ACTION_QUICKBOOT
    ) {
      return
    }

    if (!HeartRateBleService.hasSavedSession(context)) {
      Log.d(TAG, "Tidak ada sesi tersimpan; tidak ada yang perlu dilanjutkan.")
      return
    }

    val interval = HeartRateBleService.savedInterval(context)
    Log.d(TAG, "Melanjutkan sesi setelah $action, interval $interval menit.")

    // minSdk proyek ini 30, jadi startForegroundService() selalu tersedia.
    context.startForegroundService(HeartRateBleService.startIntent(context, interval))
  }
}
