import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// UUID HARUS SAMA PERSIS dengan BleGattServerManager.kt di app jam tangan.
final Guid heartRateServiceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");
final Guid heartRateCharUuid = Guid("abcdef01-1234-5678-1234-56789abcdef0");
