import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/heart_rate_cubit.dart';
import 'cubit/ble_server_cubit.dart';

class HeartRatePage extends StatelessWidget {
  const HeartRatePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. BLOC LISTENER: Bertugas "mendengarkan" saat ada detak jantung baru
    // lalu melempar angkanya ke BleServerCubit untuk dipancarkan
    return BlocListener<HeartRateCubit, HeartRateState>(
      listener: (context, state) {
        if (state is HeartRateRunning && state.bpm > 0) {
          context.read<BleServerCubit>().updateBpm(state.bpm.toInt());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070C14),
        body: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double size = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;

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
                    border: Border.all(
                      color: const Color(0xFF00E5FF),
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: BlocBuilder<HeartRateCubit, HeartRateState>(
                      builder: (context, state) {
                        if (state is HeartRateRunning) {
                          return _buildRunningUI(
                            context,
                            state.bpm,
                            state.interval,
                          );
                        } else if (state is HeartRateError) {
                          return _buildErrorUI(context, state.message);
                        } else if (state is HeartRateInitial) {
                          // Memasukkan interval yang sedang dipilih ke UI
                          return _buildInitialUI(
                            context,
                            state.selectedInterval,
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRunningUI(BuildContext context, double bpm, int interval) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 3. INDIKATOR BLE: Menambahkan ikon Bluetooth di sebelah ikon jantung
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/heart_icon.png',
              width: 32, // Sedikit dikecilkan agar muat dengan ikon Bluetooth
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            BlocBuilder<BleServerCubit, BleServerState>(
              builder: (context, bleState) {
                return Icon(
                  Icons.bluetooth_connected,
                  size: 20,
                  // Ikon menyala biru jika BLE aktif memancar, redup jika tidak
                  color: bleState is BleServerBroadcasting
                      ? const Color(0xFF00E5FF)
                      : Colors.white24,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              // Jika BPM 0 tampilkan -- (loading), jika tidak tampilkan angka
              bpm == 0 ? "--" : bpm.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              "Bpm",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          bpm == 0 ? "Membaca sensor..." : "Update tiap $interval menit",
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
        const SizedBox(height: 4),

        // 4. TOMBOL BERHENTI: Matikan sensor DAN matikan pancaran BLE
        GestureDetector(
          onTap: () {
            context.read<HeartRateCubit>().stopSensor();
            context.read<BleServerCubit>().stopBroadcasting();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "BERHENTI",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialUI(BuildContext context, int currentInterval) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          "assets/heart_icon.png",
          width: 40,
          height: 40,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 6),
        const Text(
          "Pilih Interval:",
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 2),
        // Baris untuk opsi interval
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _intervalButton(context, 1, currentInterval),
            const SizedBox(width: 4),
            _intervalButton(context, 3, currentInterval),
            const SizedBox(width: 4),
            _intervalButton(context, 5, currentInterval),
          ],
        ),
        const SizedBox(height: 6),

        // 5. TOMBOL MULAI: Nyalakan sensor DAN nyalakan pancaran BLE
        GestureDetector(
          onTap: () {
            context.read<HeartRateCubit>().startSensor();
            context.read<BleServerCubit>().startBroadcasting();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "MULAI",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Widget custom untuk tombol angka 1, 3, 5
  Widget _intervalButton(
    BuildContext context,
    int minutes,
    int currentInterval,
  ) {
    final isSelected = minutes == currentInterval;
    return GestureDetector(
      onTap: () => context.read<HeartRateCubit>().setInterval(minutes),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0075FF) : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF0075FF) : Colors.white54,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            "$minutes'",
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorUI(BuildContext context, String message) {
    return GestureDetector(
      // 6. TOMBOL ERROR: Saat diklik ulang, coba hidupkan keduanya lagi
      onTap: () {
        context.read<HeartRateCubit>().startSensor();
        context.read<BleServerCubit>().startBroadcasting();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 30),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            const SizedBox(height: 8),
            const Text(
              "Tap untuk coba lagi",
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
