package com.example.hr_07_ble_dasar

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class HeartRateDbHelper(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {
  companion object {
    const val DB_NAME = "heart_rate.db"
    const val DB_VERSION = 1
    const val TABLE = "readings"
  }

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL(
        """
        CREATE TABLE IF NOT EXISTS $TABLE (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bpm REAL NOT NULL,
          accuracy INTEGER NOT NULL,
          time INTEGER NOT NULL
        )
        """.trimIndent()
    )
  }
  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
      // Belum ada migrasi; skema masih sama dengan versi 1.
  }

  fun insertReading(bpm: Double, accuracy: Int, timeMillis: Long) {
    val values = ContentValues().apply {
        put("bpm", bpm)
        put("accuracy", accuracy)
        put("time", timeMillis)
    }
    writableDatabase.insert(TABLE, null, values)
  }
}