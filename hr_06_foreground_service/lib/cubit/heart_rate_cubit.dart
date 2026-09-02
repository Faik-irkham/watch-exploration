import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/services.dart';
import 'package:hr_06_foreground_service/heart_rate_database.dart';
import 'package:hr_06_foreground_service/models/heart_rate_reading.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial(selectedInterval: 1));

  static const _channel = EventChannel('heart_rate/stream');
  StreamSubscription? _subscription;
  Timer? _intervalTimer;
  int _selectedInterval = 1;

  // Fungsi untuk mengubah pilihan interval dari UI
  void setInterval(int minutes) {
    _selectedInterval = minutes;
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  Future<void> startSensor() async {
    final status = await Permission.sensors.request();

    if (!status.isGranted) {
      emit(HeartRateError("Izin sensor ditolak."));
      return;
    }

    // Ubah status jadi running (BPM 0 berarti sedang memuat)
    emit(HeartRateRunning(bpm: 0.0, interval: _selectedInterval));

    // Ambil data untuk pertama kali
    _startReading();

    // Jadwalkan pembacaan berulang sesuai interval
    _intervalTimer = Timer.periodic(Duration(minutes: _selectedInterval), (
      timer,
    ) {
      _startReading();
    });
  }

  void _startReading() {
    // Jika sensor masih aktif membaca, abaikan agar tidak dobel
    if (_subscription != null) return;

    _subscription = _channel.receiveBroadcastStream().listen(
      (event) {
        final data = Map<String, dynamic>.from(event as Map);
        final currentBpm = (data['bpm'] as num?)?.toDouble() ?? 0.0;
        final accuracy = (data['accuracy'] as num?)?.toInt() ?? 0;

        // Tunggu hingga sensor benar-benar mendeteksi detak jantung (>0)
        if (currentBpm > 0) {
          // Update UI
          emit(HeartRateRunning(bpm: currentBpm, interval: _selectedInterval));

          // Simpan ke SQLite
          final reading = HearRateReading(
            bpm: currentBpm,
            accuracy: accuracy,
            time: DateTime.now(),
          );
          HeartRateDatabase.instance.insertReading(reading);

          //Hentikan sensor untuk menghemat baterai sampai interval berikutnya!
          _subscription?.cancel();
          _subscription = null;
        }
      },
      onError: (error) {
        emit(HeartRateError("Error dari sensor: $error"));
        _subscription?.cancel();
        _subscription = null;
      },
    );
  }

  void stopSensor() {
    _intervalTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;

    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  @override
  Future<void> close() {
    _intervalTimer?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
