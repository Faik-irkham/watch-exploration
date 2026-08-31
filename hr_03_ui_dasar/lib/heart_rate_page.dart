import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class HeartRatePage extends StatefulWidget {
  const new({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  static const _channel = EventChannel('heart_rate/stream');
  double _bpm = 0;
  bool _running = false;

  Future<void> _start() async {
    final status = await Permission.sensors.request();

    if (!status.isGranted) {
      debugPrint("Izin sensor ditolak atau belum dikonfigurasi di Manifest.");
      return;
    }

    setState(() => _running = true);

    _channel.receiveBroadcastStream().listen(
      (event) {
        // Karena Kotlin mengirimkan Map, kita konversi dengan aman di sini
        final data = Map<String, dynamic>.from(event as Map);
        setState(() => _bpm = (data['bpm'] as num?)?.toDouble() ?? 0);
      },
      onError: (error) {
        debugPrint("Error dari sensor: \$error");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _running
            ? Text(
                "${_bpm.toStringAsFixed(0)} BPM",
                style: TextStyle(fontSize: 40),
              )
            : TextButton(
                onPressed: _start,
                child: const Text("Izinkan dan Mulai"),
              ),
      ),
    );
  }
}
