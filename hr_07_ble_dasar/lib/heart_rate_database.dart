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
}
