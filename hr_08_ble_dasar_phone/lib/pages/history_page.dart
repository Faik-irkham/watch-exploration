import 'package:flutter/material.dart';

import '../services/hr_database.dart';
import '../models/reading.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HeartRateReading> _readings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final data = await HrDatabase.instance.getReadings();
    if (!mounted) return;
    setState(() {
      _readings = data;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus semua riwayat?"),
        content: const Text("Tindakan ini tidak bisa dibatalkan."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await HrDatabase.instance.clearReadings();
      _load();
    }
  }

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Detak Jantung"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _readings.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _readings.isEmpty
          ? const Center(child: Text("Belum ada riwayat"))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _readings.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final r = _readings[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                    ),
                    title: Text("${r.bpm} bpm"),
                    trailing: Text(_formatTime(r.time)),
                  );
                },
              ),
            ),
    );
  }
}
