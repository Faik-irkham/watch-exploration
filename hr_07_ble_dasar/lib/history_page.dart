import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'heart_rate_database.dart';
import 'models/heart_rate_reading.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HearRateReading> _readings = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final data = await HeartRateDatabase.instance.getReadings();
    if (!mounted) return;
    setState(() {
      _readings = data;
      _loading = false;
    });
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await HeartRateDatabase.instance.exportCsv();
      // Path lengkapnya terlalu panjang untuk layar jam; yang utuh ke logcat.
      debugPrint('CSV riwayat diekspor ke: $path');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan: ${p.basename(path)}',
            style: const TextStyle(fontSize: 10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal ekspor: $e', style: const TextStyle(fontSize: 10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const threshold = 200.0;
    if (velocity <= -threshold) {
      Navigator.of(context).maybePop();
    }
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
      body: GestureDetector(
        onHorizontalDragEnd: _handleSwipe,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Riwayat Detak Jantung",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Ukuran dan padding dipangkas habis: di layar bulat, tinggi
                  // baris judul ikut memakan ruang daftar di bawahnya.
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    tooltip: "Ekspor CSV",
                    onPressed: _readings.isEmpty || _exporting ? null : _export,
                    icon: _exporting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF00E5FF),
                            ),
                          )
                        : Icon(
                            Icons.save_alt,
                            size: 14,
                            color: _readings.isEmpty
                                ? Colors.white24
                                : const Color(0xFF00E5FF),
                          ),
                  ),
                ],
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
                        onRefresh: _load,
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
      ),
    );
  }
}
