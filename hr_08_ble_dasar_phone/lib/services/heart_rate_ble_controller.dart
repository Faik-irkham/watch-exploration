import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants.dart';
import '../models/reading.dart';
import 'hr_database.dart';

enum ConnectionStatus {
  idle,
  bluetoothOff,
  scanning,
  connecting,
  connected,
  disconnected,
  error,
}

/// Menangani semua urusan BLE: minta izin, cek status Bluetooth, scan,
/// connect, subscribe notifikasi, dan simpan tiap bacaan ke database.
/// UI (HrReceiverPage) cukup "mendengarkan" objek ini lewat ChangeNotifier,
/// tidak perlu tahu detail BLE sama sekali.
class HeartRateBleController extends ChangeNotifier {
  ConnectionStatus status = ConnectionStatus.idle;
  String statusMessage = "Menyiapkan...";
  int? bpm;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  Future<void> start() async {
    final granted = await _requestPermissions();
    if (!granted) {
      _setStatus(ConnectionStatus.error, "Izin Bluetooth/Lokasi ditolak.");
      return;
    }

    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        if (status == ConnectionStatus.bluetoothOff ||
            status == ConnectionStatus.idle) {
          _startScan();
        }
      } else {
        _scanSub?.cancel();
        _valueSub?.cancel();
        bpm = null;
        _setStatus(
          ConnectionStatus.bluetoothOff,
          "Bluetooth mati. Nyalakan dulu.",
        );
      }
    });
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
        statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
  }

  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      statusMessage = "Tidak bisa menyalakan otomatis. Nyalakan manual dari Quick Settings, lalu buka lagi app ini.";
      notifyListeners();
    }
  }

  Future<void> _startScan() async {
    _setStatus(ConnectionStatus.scanning, "Mencari jam tangan...");

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(heartRateServiceUuid)) {
          FlutterBluePlus.stopScan();
          _connectTo(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [heartRateServiceUuid],
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _scanSub?.cancel();
    _device = device;

    _setStatus(
      ConnectionStatus.connecting,
      "Menyambungkan ke ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}...",
    );

    _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _valueSub?.cancel();
        bpm = null;
        _setStatus(ConnectionStatus.disconnected, "Terputus. Mencari ulang...");
        _startScan();
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.nonprofit,
      );
      await _subscribeToHeartRate(device);
    } catch (e) {
      _setStatus(ConnectionStatus.error, "Gagal menyambung: $e");
    }
  }

  Future<void> _subscribeToHeartRate(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? target;

    for (final service in services) {
      if (service.uuid == heartRateServiceUuid) {
        for (final c in service.characteristics) {
          if (c.uuid == heartRateCharUuid) {
            target = c;
            break;
          }
        }
      }
    }

    if (target == null) {
      _setStatus(
        ConnectionStatus.error,
        "Characteristic detak jantung tidak ditemukan.",
      );
      return;
    }

    await target.setNotifyValue(true);

    _valueSub?.cancel();
    _valueSub = target.lastValueStream.listen((value) {
      if (value.isEmpty) return;
      final reading = value[0] & 0xFF;
      bpm = reading;
      notifyListeners();

      HrDatabase.instance.insertReading(
        HeartRateReading(bpm: reading, time: DateTime.now()),
      );
    });

    _setStatus(
      ConnectionStatus.connected,
      "Terhubung ke ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}",
    );
  }

  void _setStatus(ConnectionStatus newStatus, String message) {
    status = newStatus;
    statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    _valueSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}
