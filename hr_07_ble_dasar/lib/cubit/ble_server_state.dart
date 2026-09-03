part of 'ble_server_cubit.dart';

@immutable
sealed class BleServerState {}

final class BleServerInitial extends BleServerState {}

final class BleServerBroadcasting extends BleServerState {}

final class BleServerError extends BleServerState {
  final String message;

  BleServerError(this.message);
}
