package com.example.hr_07_ble_dasar

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  companion object {
    private const val CONTROL_CHANNEL = "heart_rate_service/control"
    private const val UPDATES_CHANNEL = "heart_rate_service/updates"
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger

    // Perintah dari UI Flutter -> native: start/stop sesi sensor+BLE.
    // Dipanggil dari main engine, jadi selalu reliable.
    MethodChannel(messenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          val interval = call.argument<Int>("interval") ?: 1
          val intent = Intent(this, HeartRateBleService::class.java).apply {
            action = HeartRateBleService.ACTION_START
            putExtra(HeartRateBleService.EXTRA_INTERVAL_MINUTES, interval)
          }
          ContextCompat.startForegroundService(this, intent)
          result.success(true)
        }
        "stop" -> {
          val intent = Intent(this, HeartRateBleService::class.java).apply {
            action = HeartRateBleService.ACTION_STOP
          }
          startService(intent)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }

    // Update dari native -> UI (bpm baru / status BLE / error).
    // Hanya untuk tampilan; loop di HeartRateBleService jalan terus
    // walau tidak ada yang mendengarkan channel ini.
    EventChannel(messenger, UPDATES_CHANNEL).setStreamHandler(LiveUpdateBridge)
  }
}
