package com.example.hr_07_ble_dasar

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Jembatan antara HeartRateBleService (native) dan Flutter engine yang
 * SEDANG aktif (kalau ada). Karena service sekarang berjalan di proses
 * Android yang sama dengan MainActivity (bukan isolate Dart terpisah
 * seperti sebelumnya), singleton object biasa ini cukup untuk memegang
 * EventSink yang aktif.
 *
 * Kalau tidak ada UI yang mendengarkan (app di-background/di-kill), emit
 * di bawah cukup no-op — loop sensor & BLE di service TIDAK bergantung
 * pada sink ini, jadi tetap jalan.
 *
 * Semua emit di-post ke main thread karena EventSink wajib dipanggil dari
 * situ, sedangkan pemanggilnya (sensor callback, BLE callback) bisa saja
 * datang dari thread lain.
 */

 object LiveUpdateBridge : EventChannel.StreamHandler {
  private var sink: EventChannel.EventSink? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
  }

  override fun onCancel(arguments: Any?) {
      sink = null
  }

  private fun emit(payload: Map<String, Any?>) {
      mainHandler.post { sink?.success(payload) }
  }

  fun emitBpm(bpm: Double, interval: Int) =
    emit(mapOf("type" to "bpm", "bpm" to bpm, "interval" to interval))

  fun emitSensorError(message: String) =
    emit(mapOf("type" to "sensor_error", "message" to message))

  fun emitBleStatus(status: String, message: String? = null) =
    emit(mapOf("type" to "ble_status", "status" to status, "message" to message))
 }