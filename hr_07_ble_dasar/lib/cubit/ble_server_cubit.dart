import 'package:bloc/bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

part 'ble_server_state.dart';

class BleServerCubit extends Cubit<BleServerState> {
  BleServerCubit() : super(BleServerInitial());

  static const _methodChannel = MethodChannel('ble_server/methods');

  Future<void> startBroadcasting() async {
    // 1. Minta Izin Bluetooth khusus untuk Advertising (Wajib di Android 12+ / WearOS 3+)
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    if (statuses.values.any((status) => !status.isGranted)) {
      emit(
        BleServerError(
          "Izin Bluetooth Advertise dibutuhkan untuk memancarkan sinyal.",
        ),
      );
      return;
    }

    // 2. Perintahkan Kotlin menyalakan GATT Server
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

  // Fungsi ini akan dipanggil setiap kali sensor jam tangan membaca detak jantung baru
  Future<void> updateBpm(int bpm) async {
    // mengirim data jika jam sedang memancarkan sinyal
    if (state is BleServerBroadcasting) {
      try {
        await _methodChannel.invokeMethod('updateBpm', {'bpm': bpm});
      } catch (e) {
        debugPrint("Gagal update BPM ke GATT Server: $e");
      }
    }
  }

  @override
  Future<void> close() {
    stopBroadcasting();
    return super.close();
  }
}
