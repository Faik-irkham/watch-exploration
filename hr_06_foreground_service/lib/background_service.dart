import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  // Tugas service ini HANYA menahan agar aplikasi tidak di-kill OS.
  // Otak pembacaan interval tetap dikerjakan oleh Cubit.

  service.on('stopService').listen((event) {
    service.stopSelf(); // Matikan tameng saat tombol berhenti ditekan
  });
}
