import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/services.dart';
import 'package:hr_07_ble_dasar/heart_rate_database.dart';
import 'package:hr_07_ble_dasar/models/heart_rate_reading.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial(selectedInterval: 1));

  static const _channel = EventChannel('heart_rate/stream');
  StreamSubscription? _subscription;
  Timer? _intervalTimer;
  int _selectedInterval = 1;

  void setInterval(int minutes) {
    _selectedInterval = minutes;
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  Future<void> startSensor() async {
    final sensorStatus = await Permission.sensors.request();
    final notifStatus = await Permission.notification.request();

    if (!sensorStatus.isGranted) {
      emit(HeartRateError("Izin sensor ditolak."));
      return;
    }

    emit(HeartRateRunning(bpm: 0.0, interval: _selectedInterval));

    // 1. NYALAKAN GUARD FOREGROUND SERVICE AGAR APP TIDAK DI-KILL OS
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }

    // 2. Mulai pembacaan dan Timer
    _startReading();
    _intervalTimer = Timer.periodic(Duration(minutes: _selectedInterval), (
      timer,
    ) {
      _startReading();
    });
  }

  void _startReading() {
    if (_subscription != null) return;

    _subscription = _channel.receiveBroadcastStream().listen(
      (event) {
        final data = Map<String, dynamic>.from(event as Map);
        final currentBpm = (data['bpm'] as num?)?.toDouble() ?? 0.0;
        final accuracy = (data['accuracy'] as num?)?.toInt() ?? 0;

        if (currentBpm > 0) {
          emit(HeartRateRunning(bpm: currentBpm, interval: _selectedInterval));

          final reading = HearRateReading(
            // <-- Sesuaikan jika nama class Anda HeartRateReading
            bpm: currentBpm,
            accuracy: accuracy,
            time: DateTime.now(),
          );
          HeartRateDatabase.instance.insertReading(reading);

          _subscription?.cancel();
          _subscription = null;
        }
      },
      onError: (error) {
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  void stopSensor() {
    _intervalTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;

    // 3. MATIKAN TAMENG FOREGROUND SERVICE
    FlutterBackgroundService().invoke('stopService');

    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  @override
  Future<void> close() {
    _intervalTimer?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
