import 'package:flutter/services.dart';

class HeartRateServiceBridge {
  HeartRateServiceBridge._();

  static const MethodChannel _control = MethodChannel(
    'heart_rate_service/control',
  );
  static const EventChannel _updates = EventChannel(
    'heart_rate_service/updates',
  );

  static Stream<Map<String, dynamic>>? _stream;
  static Stream<Map<String, dynamic>> get updates {
    return _stream ??= _updates.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event as Map),
    );
  }

  static Future<void> start(int intervalMinutes) {
    return _control.invokeMethod('start', {'interval': intervalMinutes});
  }

  static Future<void> stop() {
    return _control.invokeMethod('stop');
  }
}
