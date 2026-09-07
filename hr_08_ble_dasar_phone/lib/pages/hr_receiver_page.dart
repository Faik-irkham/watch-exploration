import 'package:flutter/material.dart';
import 'package:hr_08_ble_dasar_phone/pages/history_page.dart';

import '../../services/heart_rate_ble_controller.dart';

class HrReceiverPage extends StatefulWidget {
  const HrReceiverPage({super.key});

  @override
  State<HrReceiverPage> createState() => _HrReceiverPageState();
}

class _HrReceiverPageState extends State<HrReceiverPage> {
  late final HeartRateBleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HeartRateBleController();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final clock = "${two(t.hour)}:${two(t.minute)}:${two(t.second)}";
    final today = DateTime.now();
    final sameDay =
        t.year == today.year && t.month == today.month && t.day == today.day;
    // Waktu yang ditampilkan berasal dari jam, bukan dari ponsel. Kalau
    // jam sempat mati lalu menyala lagi dengan tanggal berbeda, selisihnya
    // harus kelihatan — karena itu tanggal ikut ditampilkan bila bukan
    // hari ini.
    return sameDay ? clock : "${two(t.day)}/${two(t.month)} $clock";
  }

  Color _statusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.greenAccent;
      case ConnectionStatus.error:
      case ConnectionStatus.bluetoothOff:
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
      appBar: AppBar(
        title: const Text("Penerima Detak Jantung"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "Riwayat",
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HistoryPage()));
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final color = _statusColor(_controller.status);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bluetooth_searching, color: color, size: 48),
                const SizedBox(height: 12),
                Text(
                  _controller.statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Text(
                  _controller.bpm == null ? "--" : "${_controller.bpm}",
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "BPM",
                  style: TextStyle(fontSize: 16, color: Colors.white54),
                ),
                const SizedBox(height: 8),
                Text(
                  _controller.lastReadingTime == null
                      ? "Belum ada kiriman masuk"
                      : "Diukur jam ${_formatTime(_controller.lastReadingTime!)}",
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                if (_controller.lastReceivedAt != null)
                  Text(
                    "Diterima ${_formatTime(_controller.lastReceivedAt!)}",
                    style: const TextStyle(fontSize: 11, color: Colors.white24),
                  ),
                const SizedBox(height: 32),
                if (_controller.status == ConnectionStatus.bluetoothOff)
                  ElevatedButton(
                    onPressed: _controller.turnOnBluetooth,
                    child: const Text("Nyalakan Bluetooth"),
                  ),
                if (_controller.status == ConnectionStatus.error ||
                    _controller.status == ConnectionStatus.disconnected)
                  ElevatedButton(
                    onPressed: _controller.start,
                    child: const Text("Coba Lagi"),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
