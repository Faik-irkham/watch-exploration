import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:hr_07_ble_dasar/native_bridge/heart_rate_service_bridge.dart';
import 'package:meta/meta.dart';
import 'package:permission_handler/permission_handler.dart';

part 'heart_rate_state.dart';

class HeartRateCubit extends Cubit<HeartRateState> {
  HeartRateCubit() : super(HeartRateInitial(selectedInterval: 1)) {
    _subscription = HeartRateServiceBridge.updates.listen(_onServiceEvent);
  }

  int _selectedInterval = 1;
  StreamSubscription? _subscription;

  void _onServiceEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'bpm':
        emit(
          HeartRateRunning(
            bpm: (event['bpm'] as num).toDouble(),
            interval: (event['interval'] as num).toInt(),
          ),
        );
        break;
      case 'sensor_error':
        emit(HeartRateError(event['message'] as String? ?? 'Sensor error'));
        break;
    }
  }

  void setInterval(int minutes) {
    _selectedInterval = minutes;
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  Future<void> startSensor() async {
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

    try {
      // Satu perintah ini menyalakan foreground service native yang
      // menangani sensor DAN BLE sekaligus.
      await HeartRateServiceBridge.start(_selectedInterval);
    } catch (e) {
      emit(HeartRateError("Gagal memulai layanan: $e"));
    }
  }

  void stopSensor() {
    HeartRateServiceBridge.stop();
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
