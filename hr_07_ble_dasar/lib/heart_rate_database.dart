import 'dart:io';

import 'package:hr_07_ble_dasar/models/heart_rate_reading.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class HeartRateDatabase {
  HeartRateDatabase._();
  static final HeartRateDatabase instance = HeartRateDatabase._();

  static const _dbName = 'heart_rate.db';
  static const _table = 'readings';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bpm REAL NOT NULL,
          accuracy INTEGER NOT NULL,
          time INTEGER NOT NULL
          )
      ''');
      },
    );
    return _db!;
  }

  Future<void> insertReading(HearRateReading reading) async {
    final db = await database;
    await db.insert(_table, reading.toMap());
  }

  Future<List<HearRateReading>> getReadings() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'time DESC');
    return rows.map(HearRateReading.fromMap).toList();
  }

  Future<void> clearReadings() async {
    final db = await database;
    await db.delete(_table);
  }

  /// Menulis seluruh isi tabel ke satu berkas CSV di penyimpanan privat
  /// aplikasi, lalu mengembalikan path lengkapnya.
  ///
  /// Sengaja tidak memakai `path_provider` supaya tidak menambah dependensi:
  /// sqflite sudah tahu letak folder basis data, dan induk folder itu adalah
  /// folder data aplikasi. Berkasnya diambil dengan:
  ///
  /// ```
  ///   adb shell "run-as com.example.hr_07_ble_dasar \
  ///     cat exports/<nama>.csv" > watch.csv
  /// ```
  ///
  /// Kolom `time_millis` sengaja ditaruh paling depan dan ditulis apa adanya:
  /// itulah kunci yang memasangkan baris ini dengan baris di basis data
  /// ponsel. Kolom `time_local` hanya untuk dibaca manusia.
  Future<String> exportCsv() async {
    final readings = await getReadings();

    final exportDir = Directory(
      p.join(p.dirname(await getDatabasesPath()), 'exports'),
    );
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }

    final file = File(p.join(exportDir.path, 'hr_07_readings_${_stamp()}.csv'));

    final buffer = StringBuffer()
      ..writeln('time_millis,time_local,bpm,accuracy');
    // getReadings() mengurutkan menurun; dibalik supaya CSV urut naik dan
    // mudah disandingkan baris per baris dengan ekspor dari ponsel.
    for (final r in readings.reversed) {
      buffer.writeln(
        '${r.time.millisecondsSinceEpoch},'
        '${r.time.toIso8601String()},'
        '${r.bpm},'
        '${r.accuracy}',
      );
    }

    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
