import 'package:bloc/bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

part 'ble_server_state.dart';

class BleServerCubit extends Cubit<BleServerState> {
  BleServerCubit() : super(BleServerInitial());

  static const _methodChannel = MethodChannel('ble_server/methods');

  Future<void> startBroadcasting() async {
    // Izin sudah ditangani di awal oleh HeartRateCubit,
    // jadi langsung eksekusi perintah ke Kotlin.
    try {
      await _methodChannel.invokeMethod('startBroadcasting');
      emit(BleServerBroadcasting());
    } catch (e) {
      emit(BleServerError("Gagal memulai broadcast: $e"));
    }
  }

  Future<void> stopBroadcasting() async {
    try {
      await _methodChannel.invokeMethod('stopBroadcasting');
      emit(BleServerInitial());
    } catch (e) {
      emit(BleServerError("Gagal menghentikan broadcast: $e"));
    }
  }

  @override
  Future<void> close() {
    stopBroadcasting();
    return super.close();
  }
}
