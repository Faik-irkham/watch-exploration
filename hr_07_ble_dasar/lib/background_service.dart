import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hr_07_ble_dasar/heart_rate_database.dart';
import 'package:hr_07_ble_dasar/models/heart_rate_reading.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'heart_rate_channel',
    'Pemantau Detak Jantung',
    description: 'Menjalankan aplikasi agar tidak ditutup sistem',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'heart_rate_channel',
      initialNotificationTitle: 'Sensor Aktif',
      initialNotificationContent: 'Aplikasi berjalan di latar belakang...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Deklarasi Channel khusus untuk Isolate Background
  const heartRateChannel = EventChannel('heart_rate/stream');
  const bleMethodChannel = MethodChannel('ble_server/methods');

  Timer? intervalTimer;
  StreamSubscription? sensorSubscription;
  int currentInterval = 1;

  // FUNGSI INTI: Membaca sensor, menyimpan ke DB, dan mengirim BLE
  void readSensor() {
    if (sensorSubscription != null) return;

    sensorSubscription = heartRateChannel.receiveBroadcastStream().listen(
      (event) async {
        final data = Map<String, dynamic>.from(event as Map);
        final currentBpm = (data['bpm'] as num?)?.toDouble() ?? 0.0;
        final accuracy = (data['accuracy'] as num?)?.toInt() ?? 0;

        if (currentBpm > 0) {
          // 1. Simpan ke SQLite
          final reading = HearRateReading(
            bpm: currentBpm,
            accuracy: accuracy,
            time: DateTime.now(),
          );
          await HeartRateDatabase.instance.insertReading(reading);

          // 2. Kirim Update ke BLE GATT Server secara langsung!
          try {
            await bleMethodChannel.invokeMethod('updateBpm', {
              'bpm': currentBpm.toInt(),
            });
          } catch (e) {
            // Abaikan jika gagal (misal server BLE belum dinyalakan)
          }

          // 3. Kirim data ke UI (jika layar sedang menyala)
          service.invoke('updateUI', {
            'bpm': currentBpm,
            'interval': currentInterval,
          });

          // 4. Matikan sensor untuk menghemat baterai sampai interval berikutnya
          sensorSubscription?.cancel();
          sensorSubscription = null;
        }
      },
      onError: (error) {
        sensorSubscription?.cancel();
        sensorSubscription = null;
      },
    );
  }

  // MENDENGARKAN PERINTAH DARI UI (CUBIT)
  service.on('setStart').listen((event) {
    currentInterval = event?['interval'] ?? 1;

    // Lakukan pembacaan instan saat pertama kali ditekan
    readSensor();

    // Jalankan timer untuk pembacaan berikutnya
    intervalTimer?.cancel();
    intervalTimer = Timer.periodic(Duration(minutes: currentInterval), (timer) {
      readSensor();
    });
  });

  service.on('setStop').listen((event) {
    intervalTimer?.cancel();
    sensorSubscription?.cancel();
    sensorSubscription = null;
    service.stopSelf(); // Matikan Background Service
  });
}
