import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// UUID HARUS SAMA PERSIS dengan BleGattServerManager.kt di app jam tangan.
final Guid heartRateServiceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");
final Guid heartRateCharUuid = Guid("abcdef01-1234-5678-1234-56789abcdef0");

/// Versi susunan payload. Harus sama dengan
/// `BleGattServerManager.PROTOCOL_VERSION` di sisi jam.
const int heartRateProtocolVersion = 2;

/// Panjang tetap payload notify, dalam byte.
const int heartRatePayloadSize = 10;

/// Satu bacaan sebagaimana dikirim lewat udara.
///
/// Susunan 10 byte, big-endian — sama persis dengan `encode()` di
/// BleGattServerManager.kt:
///
///   byte [0]     versi protokol
///   byte [1]     bpm, unsigned 0..255
///   byte [2..9]  waktu bacaan diambil DI JAM, epoch milidetik (Int64)
///
/// Waktu ikut dikirim supaya kolom `time` di SQLite ponsel berisi angka
/// yang sama persis dengan `time` di SQLite jam. Pengiriman sendiri masih
/// sekali tembak — bacaan yang lewat tidak disusulkan — jadi kelengkapan
/// data bergantung pada langkah rekonsiliasi belakangan yang memasangkan
/// kedua tabel lewat kolom itu. Kalau ponsel memakai waktu terima,
/// pemasangan tersebut mustahil dilakukan.
class HeartRatePacket {
  final int bpm;
  final DateTime time;

  const HeartRatePacket({required this.bpm, required this.time});

  /// Mengembalikan null kalau payload tidak sesuai kontrak. Pemanggil
  /// sebaiknya memakai [versionOf] untuk menyusun pesan kesalahan.
  static HeartRatePacket? parse(List<int> value) {
    if (value.length < heartRatePayloadSize) return null;
    if (value[0] != heartRateProtocolVersion) return null;

    final bpm = value[1] & 0xFF;
    if (bpm <= 0) return null;

    var millis = 0;
    for (var i = 0; i < 8; i++) {
      millis = (millis << 8) | (value[2 + i] & 0xFF);
    }
    // Penjaga kewarasan: menolak cap waktu yang mustahil (jam belum
    // tersinkron, atau byte tergeser) supaya tidak masuk ke riwayat.
    if (millis <= 0) return null;

    return HeartRatePacket(
      bpm: bpm,
      time: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }

  /// Versi protokol yang tertulis di payload, atau null kalau kosong.
  static int? versionOf(List<int> value) =>
      value.isEmpty ? null : value[0] & 0xFF;
}
