import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/services.dart';
import 'package:hr_04_cubit_refactor/heart_rate_database.dart';
import 'package:hr_04_cubit_refactor/models/hear_rate_reading.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial());

  static const _channel = EventChannel('heart_rate/stream');
  StreamSubscription? _subscription;

  Future<void> startSensor() async {
    // 1. Meminta izin sensor
    final status = await Permission.sensors.request();

    if (!status.isGranted) {
      emit(HeartRateError("Izin sensor ditolak."));
      return;
    }

    // 2. Mengubah state menjadi running dengan nilai awal 0
    emit(HeartRateRunning(0.0));

    // 3. Mulai mendengarkan stream dari Native (Kotlin/Java)
    _subscription = _channel.receiveBroadcastStream().listen(
      (event) {
        final data = Map<String, dynamic>.from(event as Map);
        final currentBpm = (data['bpm'] as num?)?.toDouble() ?? 0.0;
        final accuracy = (data['accuracy'] as num?)?.toInt() ?? 0;

        // Update state ke UI
        emit(HeartRateRunning(currentBpm));

        // Simpan ke database jika nilai BPM valid (> 0)
        if (currentBpm > 0) {
          final reading = HearRateReading(
            bpm: currentBpm,
            accuracy: accuracy,
            time: DateTime.now(),
          );
          HeartRateDatabase.instance.insertReading(reading);
        }
      },
      onError: (error) {
        emit(HeartRateError("Error dari sensor: $error"));
      },
    );
  }

  @override
  Future<void> close() {
    // Hentikan langganan stream saat cubit dihancurkan untuk mencegah memory leak
    _subscription?.cancel();
    return super.close();
  }
}
