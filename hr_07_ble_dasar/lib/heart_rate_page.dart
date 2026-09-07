import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/heart_rate_cubit.dart';
import 'cubit/ble_server_cubit.dart';
import 'history_page.dart';

class HeartRatePage extends StatelessWidget {
  const HeartRatePage({super.key});

  void _handleSwipe(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const threshold = 200.0;

    if (velocity <= -threshold) {
      SystemNavigator.pop();
    } else if (velocity >= threshold) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HistoryPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070C14),
      body: GestureDetector(
        onHorizontalDragEnd: (details) => _handleSwipe(context, details),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Center(
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
                      border: Border.all(
                        color: const Color(0xFF0075FF),
                        width: 6,
                      ),
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
                              return _buildRunningUI(context, state);
                            } else if (state is HeartRateError) {
                              return _buildErrorUI(context, state.message);
                            } else if (state is HeartRateInitial) {
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
          ],
        ),
      ),
    );
  }

  String _formatCountdown(int totalSeconds) {
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final m = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (safeSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Widget _buildRunningUI(BuildContext context, HeartRateRunning state) {
    final bpm = state.bpm;
    final interval = state.interval;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/heart_icon.png',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            BlocBuilder<BleServerCubit, BleServerState>(
              builder: (context, bleState) {
                return Icon(
                  Icons.bluetooth_connected,
                  size: 18,
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
              bpm == 0 ? "--" : bpm.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 30,
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
        const SizedBox(height: 2),
        Text(
          "Berikutnya dalam ${_formatCountdown(state.secondsUntilNext)}",
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF00E5FF),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
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
