part of 'heart_rate_cubit.dart';

@immutable
sealed class HeartRateState {}

final class HeartRateInitial extends HeartRateState {}

// State saat sensor sedang berjalan dan membaca BPM
final class HeartRateRunning extends HeartRateState {
  final double bpm;

  HeartRateRunning(this.bpm);
}

// State jika terjadi error (misal izin ditolak)
final class HeartRateError extends HeartRateState {
  final String message;

  HeartRateError(this.message);
}
