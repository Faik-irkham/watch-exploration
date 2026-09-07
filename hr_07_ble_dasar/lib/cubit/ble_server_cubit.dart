import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:hr_07_ble_dasar/native_bridge/heart_rate_service_bridge.dart';

part 'ble_server_state.dart';

class BleServerCubit extends Cubit<BleServerState> {
  BleServerCubit() : super(BleServerInitial()) {
    _subscription = HeartRateServiceBridge.updates.listen(_onServiceEvent);
  }

  StreamSubscription? _subscription;

  void _onServiceEvent(Map<String, dynamic> event) {
    if (event['type'] != 'ble_status') return;
    switch (event['status']) {
      case 'broadcasting':
        emit(BleServerBroadcasting());
        break;
      case 'stopped':
        emit(BleServerInitial());
        break;
      case 'error':
        emit(BleServerError(event['message'] as String? ?? 'BLE error'));
        break;
    }
  }

  void startBroadcasting() {}
  void stopBroadcasting() {}

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
