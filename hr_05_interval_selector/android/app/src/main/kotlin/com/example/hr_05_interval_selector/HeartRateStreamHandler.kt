package com.example.hr_05_interval_selector

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

class HeartRateStreamHandler (
  private val context: Context,
) : EventChannel.StreamHandler, SensorEventListener {
  companion object {
    private const val TAG = "HR"
  }

  private var sensorManager: SensorManager? = null
  private var heartRateSensor: Sensor? = null
  private var eventSink: EventChannel.EventSink? = null

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    sensorManager = manager

    val sensor = manager.getDefaultSensor(Sensor.TYPE_HEART_RATE)
    if (sensor == null) {
      events?.error("NO_SENSOR", "Sensor heart rate tidak tersedia di perangkat ini", null)
      return
    }
    heartRateSensor = sensor
    val registered = manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    Log.d(TAG, "registerListener heart rate => $registered")
    if(!registered) {
      events?.error(
        "REGISTER_FAILED",
        "Gagal mengaktifkan sensor. Pastikan izin Sensor tubuh diizinkan dan mode hemat daya mati.",
        null,
      )
    }
  }

  override fun onCancel(arguments: Any?) {
    sensorManager?.unregisterListener(this)
    sensorManager = null
    heartRateSensor = null
    eventSink = null
  }

  override fun onSensorChanged(event: SensorEvent?) {
    if(event == null || event.sensor.type != Sensor.TYPE_HEART_RATE) return
    val bpm = event.values.firstOrNull() ?: return
    eventSink?.success(
        mapOf(
            "bpm" to bpm,
            // 0 = tidak bisa dipercaya, 1 = rendah, 2 = sedang, 3 = tinggi
            "accuracy" to event.accuracy
        )
    )
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
    // Tidak perlu ditangani; nilai accuracy dikirim bersama tiap pembacaan.
  }
}