import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial(selectedInterval: 1)) {
    _listenToBackgroundService();
  }

  int _selectedInterval = 1;
  StreamSubscription? _uiSubscription;

  // Mendengarkan update angka dari Background Service
  void _listenToBackgroundService() {
    _uiSubscription = FlutterBackgroundService().on('updateUI').listen((event) {
      if (event != null) {
        final bpm = (event['bpm'] as num).toDouble();
        final interval = (event['interval'] as num).toInt();
        emit(HeartRateRunning(bpm: bpm, interval: interval));
      }
    });
  }

  void setInterval(int minutes) {
    _selectedInterval = minutes;
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  Future<void> startSensor() async {
    // Minta semua izin yang dibutuhkan sekaligus di sini
    final statuses = await [
      Permission.sensors,
      Permission.notification,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.sensors] != PermissionStatus.granted ||
        statuses[Permission.bluetoothAdvertise] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
      emit(HeartRateError("Izin sensor atau bluetooth ditolak."));
      return;
    }

    emit(HeartRateRunning(bpm: 0.0, interval: _selectedInterval));

    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }

    service.invoke('setStart', {'interval': _selectedInterval});
  }

  void stopSensor() {
    // Perintahkan background service untuk berhenti
    FlutterBackgroundService().invoke('setStop');
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  @override
  Future<void> close() {
    _uiSubscription?.cancel();
    return super.close();
  }
}
