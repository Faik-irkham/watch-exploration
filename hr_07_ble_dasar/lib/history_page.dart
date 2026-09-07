import 'package:flutter/material.dart';

import 'heart_rate_database.dart';
import 'models/heart_rate_reading.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<HearRateReading> _readings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (mounted) setState(() => _loading = true);
    final data = await HeartRateDatabase.instance.getReadings();
    if (!mounted) return;
    setState(() {
      _readings = data;
      _loading = false;
    });
  }

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return "$hh:$mm:$ss";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070C14),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            const Text(
              "‹ geser untuk kembali",
              style: TextStyle(color: Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 2),
            const Text(
              "Riwayat Detak Jantung",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E5FF),
                        strokeWidth: 2,
                      ),
                    )
                  : _readings.isEmpty
                  ? const Center(
                      child: Text(
                        "Belum ada riwayat",
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: reload,
                      color: const Color(0xFF00E5FF),
                      backgroundColor: const Color(0xFF070C14),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: _readings.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Colors.white12, height: 8),
                        itemBuilder: (context, index) {
                          final r = _readings[index];
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatTime(r.time),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                "${r.bpm.toStringAsFixed(0)} bpm",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
