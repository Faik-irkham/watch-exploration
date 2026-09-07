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
  int _secondsRemaining = 0;
  StreamSubscription? _subscription;
  Timer? _countdownTimer;

  void _onServiceEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'bpm':
        final interval = (event['interval'] as num).toInt();
        _secondsRemaining = interval * 60;
        emit(
          HeartRateRunning(
            bpm: (event['bpm'] as num).toDouble(),
            interval: interval,
            secondsUntilNext: _secondsRemaining,
          ),
        );
        _restartCountdown(interval);
        break;
      case 'sensor_error':
        emit(HeartRateError(event['message'] as String? ?? 'Sensor error'));
        break;
    }
  }

  void _restartCountdown(int interval) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
      } else {
        // Jaga-jaga kalau bacaan berikutnya telat datang dari native,
        // countdown tetap berputar mengikuti panjang interval.
        _secondsRemaining = interval * 60;
      }

      final current = state;
      if (current is HeartRateRunning) {
        emit(
          HeartRateRunning(
            bpm: current.bpm,
            interval: current.interval,
            secondsUntilNext: _secondsRemaining,
          ),
        );
      }
    });
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

    _secondsRemaining = _selectedInterval * 60;
    emit(
      HeartRateRunning(
        bpm: 0.0,
        interval: _selectedInterval,
        secondsUntilNext: _secondsRemaining,
      ),
    );
    _restartCountdown(_selectedInterval);

    try {
      await HeartRateServiceBridge.start(_selectedInterval);
    } catch (e) {
      emit(HeartRateError("Gagal memulai layanan: $e"));
    }
  }

  void stopSensor() {
    _countdownTimer?.cancel();
    HeartRateServiceBridge.stop();
    emit(HeartRateInitial(selectedInterval: _selectedInterval));
  }

  @override
  Future<void> close() {
    _countdownTimer?.cancel();
    _subscription?.cancel();
    return super.close();
  }
}
