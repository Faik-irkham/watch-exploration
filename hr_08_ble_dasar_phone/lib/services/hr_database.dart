import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/reading.dart';

class HrDatabase {
  HrDatabase._();
  static final HrDatabase instance = HrDatabase._();

  static const _dbName = 'hr_receiver.db';
  static const _table = 'readings';

  /// Versi 2 menambahkan indeks UNIQUE pada kolom `time`.
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bpm INTEGER NOT NULL,
            time INTEGER NOT NULL
          )
        ''');
        await _createTimeIndex(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Baris versi 1 memakai waktu TERIMA, bukan waktu ukur, sehingga
          // bisa ada dua baris berwaktu sama. Indeks UNIQUE menolak dibuat
          // kalau duplikat itu masih ada, jadi disapu dulu — yang disimpan
          // baris dengan id terkecil.
          await db.execute('''
            DELETE FROM $_table
            WHERE id NOT IN (SELECT MIN(id) FROM $_table GROUP BY time)
          ''');
          await _createTimeIndex(db);
        }
      },
    );
    return _db!;
  }

  /// Penangkal duplikat, dan alasan kenapa jam boleh mengirim ulang bacaan
  /// yang tidak yakin sudah sampai: kiriman kedua ditolak indeks ini, bukan
  /// menjadi baris kembar.
  Future<void> _createTimeIndex(Database db) => db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_readings_time ON $_table (time)',
  );

  /// @return true kalau baris ini memang baru; false kalau waktunya sudah
  /// pernah tercatat dan kiriman tersebut diabaikan.
  Future<bool> insertReading(HeartRateReading reading) async {
    final db = await database;
    final id = await db.insert(
      _table,
      reading.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // ConflictAlgorithm.ignore mengembalikan 0 kalau barisnya ditolak.
    return id != 0;
  }

  Future<List<HeartRateReading>> getReadings() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'time DESC');
    return rows.map(HeartRateReading.fromMap).toList();
  }

  Future<void> clearReadings() async {
    final db = await database;
    await db.delete(_table);
  }
}
