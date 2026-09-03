package com.example.hr_07_ble_dasar

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
  companion object {
    // Jalur untuk Sensor Internal
    private const val HEART_RATE_CHANNEL = "heart_rate/stream"

    // Jalur untuk BLE Broadcaster
    private const val BLE_SERVER_CHANNEL = "ble_server/methods"
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger

    // 1. Mendaftarkan Sensor Internal
    EventChannel(messenger, HEART_RATE_CHANNEL)
               .setStreamHandler(HeartRateStreamHandler(applicationContext))
    
    // 2. Mendaftarkan BLE Broadcaster / GATT Server
    val bleServerHandler = BleServerHandler(applicationContext)
    MethodChannel(messenger, BLE_SERVER_CHANNEL).setMethodCallHandler(bleServerHandler)
  }
}
