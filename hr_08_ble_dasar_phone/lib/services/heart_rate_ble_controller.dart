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
///
/// Kontrak dengan app jam tangan: watch mengirim TEPAT SATU notify per
/// interval. Jadi satu notify yang diterima di sini = satu baris di
/// database, tidak boleh lebih dan tidak boleh terlewat.
class HeartRateBleController extends ChangeNotifier {
  ConnectionStatus status = ConnectionStatus.idle;
  String statusMessage = "Menyiapkan...";
  int? bpm;

  /// Kapan bacaan terakhir masuk. Dipakai UI supaya kelihatan bedanya
  /// antara "terhubung tapi belum waktunya kirim" dan "terhubung tapi macet".
  DateTime? lastReceivedAt;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  /// True selama proses connect + discover + subscribe berlangsung.
  /// Mencegah scan baru dimulai di tengah-tengah dan memicu _connectTo
  /// rekursif ke device yang sama.
  bool _busy = false;
  bool _disposed = false;

  Future<void> start() async {
    final granted = await _requestPermissions();
    if (!granted) {
      _setStatus(ConnectionStatus.error, "Izin Bluetooth/Lokasi ditolak.");
      return;
    }

    await _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        if (status == ConnectionStatus.bluetoothOff ||
            status == ConnectionStatus.idle ||
            status == ConnectionStatus.error ||
            status == ConnectionStatus.disconnected) {
          unawaited(_startScan());
        }
      } else {
        unawaited(_teardownConnection());
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
      statusMessage =
          "Tidak bisa menyalakan otomatis. Nyalakan manual dari Quick Settings, lalu buka lagi app ini.";
      notifyListeners();
    }
  }

  Future<void> _startScan() async {
    // Jangan tumpuk scan di atas proses connect yang sedang jalan, dan
    // jangan pula memulai scan kedua kalau yang pertama masih berputar.
    if (_disposed || _busy || FlutterBluePlus.isScanningNow) return;

    _setStatus(ConnectionStatus.scanning, "Mencari jam tangan...");

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_busy) return;
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(heartRateServiceUuid)) {
          unawaited(_connectTo(r.device));
          break;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [heartRateServiceUuid],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _setStatus(ConnectionStatus.error, "Gagal memulai pemindaian: $e");
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {
        // stopScan boleh gagal kalau scan sudah berhenti sendiri karena timeout.
      }
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    if (_disposed || _busy) return;
    _busy = true;

    await _stopScan();
    _device = device;
    _setStatus(ConnectionStatus.connecting, "Menyambungkan ke ${_label(device)}...");

    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.nonprofit,
      );

      // PENTING: listener connectionState baru dipasang SETELAH connect
      // sukses. flutter_blue_plus me-replay state terakhir begitu stream
      // di-listen (bluetooth_device.dart:332). Kalau dipasang sebelum
      // connect, replay itu bernilai `disconnected` dan langsung memicu
      // "terputus -> scan ulang -> connect lagi" tanpa henti.
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await _subscribeToHeartRate(device);
    } catch (e) {
      _busy = false;
      _setStatus(ConnectionStatus.error, "Gagal menyambung: $e");
      unawaited(_startScan());
      return;
    }

    _busy = false;
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

    await _valueSub?.cancel();
    // Sengaja pakai onValueReceived, BUKAN lastValueStream. lastValueStream
    // me-re-emit nilai cache lama begitu di-listen
    // (bluetooth_characteristic.dart:94), sehingga tiap reconnect akan
    // menyimpan ulang bacaan interval sebelumnya sebagai baris baru.
    // onValueReceived hanya menyala saat notify betulan datang, jadi
    // 1 notify = 1 baris.
    _valueSub = target.onValueReceived.listen((value) {
      if (value.isEmpty) return;
      // Payload watch: 1 byte unsigned (lihat BleGattServerManager.updateBpm).
      final reading = value[0] & 0xFF;
      if (reading <= 0) return;

      bpm = reading;
      lastReceivedAt = DateTime.now();
      notifyListeners();

      unawaited(
        HrDatabase.instance.insertReading(
          HeartRateReading(bpm: reading, time: DateTime.now()),
        ),
      );
    });

    _setStatus(
      ConnectionStatus.connected,
      "Terhubung ke ${_label(device)}. Menunggu kiriman berikutnya...",
    );
  }

  void _onDisconnected() {
    _valueSub?.cancel();
    _valueSub = null;
    bpm = null;

    // Kalau kita memang sudah sedang mencari ulang, jangan tumpuk scan lagi.
    if (_disposed || status == ConnectionStatus.scanning) return;

    _setStatus(ConnectionStatus.disconnected, "Terputus. Mencari ulang...");
    unawaited(_startScan());
  }

  Future<void> _teardownConnection() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _valueSub?.cancel();
    _valueSub = null;
  }

  String _label(BluetoothDevice device) => device.platformName.isNotEmpty
      ? device.platformName
      : device.remoteId.str;

  void _setStatus(ConnectionStatus newStatus, String message) {
    if (_disposed) return;
    status = newStatus;
    statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _adapterSub?.cancel();
    _teardownConnection();
    _device?.disconnect();
    super.dispose();
  }
}
