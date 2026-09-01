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
        child: LayoutBuilder(
          builder: (context, constraints) {
            double size = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.minHeight;

            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0075FF), width: 6),
              ),
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFF00E5FF), width: 4),
                ),
                child: Center(
                  child: _running ? _buildRunningUI() : _buildInitialUI(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRunningUI() {
    return Column(
      children: [
        Image.asset(
          'assets/heart_icon.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _bpm.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              "Bpm",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInitialUI() {
    return GestureDetector(
      onTap: _start,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Image.asset(
            "assets/heart_icon.png",
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          const Text(
            "Izinkan dan",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.normal,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const Text(
            "Mulai",
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
