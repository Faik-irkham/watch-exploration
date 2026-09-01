package com.example.hr_04_cubit_refactor

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
  companion object {
    private const val HEART_RATE_CHANNEL = "heart_rate/stream"
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    EventChannel(messenger, HEART_RATE_CHANNEL)
               .setStreamHandler(HeartRateStreamHandler(applicationContext))
  }
}
