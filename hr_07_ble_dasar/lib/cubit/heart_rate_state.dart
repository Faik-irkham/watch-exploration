part of 'heart_rate_cubit.dart';

@immutable
sealed class HeartRateState {}

final class HeartRateInitial extends HeartRateState {
  final int selectedInterval;

  // Default interval adalah 1 menit
  HeartRateInitial({this.selectedInterval = 1});
}

final class HeartRateRunning extends HeartRateState {
  final double bpm;
  final int interval;
  final int secondsUntilNext;

  HeartRateRunning({
    required this.bpm,
    required this.interval,
    this.secondsUntilNext = 0,
  });
}

final class HeartRateError extends HeartRateState {
  final String message;

  HeartRateError(this.message);
}
