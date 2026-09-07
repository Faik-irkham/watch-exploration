import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

final Guid heartRateServiceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");
final Guid heartRateCharUuid = Guid("abcdef01-1234-5678-1234-56789abcdef0");

enum ConnectionStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
  error,
}

class HrReceiverPage extends StatefulWidget {
  const HrReceiverPage({super.key});

  @override
  State<HrReceiverPage> createState() => _HrReceiverPageState();
}

class _HrReceiverPageState extends State<HrReceiverPage> {
  ConnectionStatus _status = ConnectionStatus.idle;
  String _statusMessage = "Menyiapkan...";
  int? _bpm;
  BluetoothDevice? _device;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  Future<void> _startFlow() async {
    final granted = await _requestPermissions();
    if (!granted) {
      setState(() {
        _status = ConnectionStatus.error;
        _statusMessage = "Izin Bluetooth/Lokasi ditolak.";
      });
      return;
    }
    _startScan();
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

  Future<void> _startScan() async {
    setState(() {
      _status = ConnectionStatus.scanning;
      _statusMessage = "Mencari jam tangan...";
    });

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

    setState(() {
      _status = ConnectionStatus.connecting;
      _statusMessage =
          "Menyambungkan ke ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}...";
    });

    _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _valueSub?.cancel();
        if (mounted) {
          setState(() {
            _status = ConnectionStatus.disconnected;
            _statusMessage = "Terputus. Mencari ulang...";
            _bpm = null;
          });
        }
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
      if (mounted) {
        setState(() {
          _status = ConnectionStatus.error;
          _statusMessage = "Gagal menyambung: $e";
        });
      }
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
      setState(() {
        _status = ConnectionStatus.error;
        _statusMessage = "Characteristic detak jantung tidak ditemukan.";
      });
      return;
    }

    await target.setNotifyValue(true);

    _valueSub?.cancel();
    _valueSub = target.lastValueStream.listen((value) {
      if (value.isEmpty) return;
      final bpm = value[0] & 0xFF;
      if (mounted) setState(() => _bpm = bpm);
    });

    if (mounted) {
      setState(() {
        _status = ConnectionStatus.connected;
        _statusMessage =
            "Terhubung ke ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}";
      });
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _valueSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Color _statusColor() {
    switch (_status) {
      case ConnectionStatus.connected:
        return Colors.greenAccent;
      case ConnectionStatus.error:
        return Colors.redAccent;
      case ConnectionStatus.scanning:
      case ConnectionStatus.connecting:
        return Colors.amberAccent;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Penerima Detak Jantung")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching, color: _statusColor(), size: 48),
            const SizedBox(height: 12),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: _statusColor(), fontSize: 14),
            ),
            const SizedBox(height: 24),
            Text(
              _bpm == null ? "--" : "$_bpm",
              style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
            ),
            const Text(
              "BPM",
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
            const SizedBox(height: 32),
            if (_status == ConnectionStatus.error ||
                _status == ConnectionStatus.disconnected)
              ElevatedButton(
                onPressed: _startFlow,
                child: const Text("Coba Lagi"),
              ),
          ],
        ),
      ),
    );
  }
}
