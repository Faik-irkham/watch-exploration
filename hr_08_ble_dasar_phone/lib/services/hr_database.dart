import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/reading.dart';

class HrDatabase {
  HrDatabase._();
  static final HrDatabase instance = HrDatabase._();

  static const _dbName = 'hr_receiver.db';
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
            bpm INTEGER NOT NULL,
            time INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> insertReading(HeartRateReading reading) async {
    final db = await database;
    await db.insert(_table, reading.toMap());
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
