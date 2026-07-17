import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/car_profile.dart';
import '../models/workshop_settings.dart';

class DatabaseService {
  Database? _db;
  int _userId = 0;

  void setUserId(int userId) => _userId = userId;
  int get userId => _userId;

  Future<void> init() async {
    final path = join(await getDatabasesPath(), 'dyno_diy.db');
    _db = await openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS calibrations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              carId INTEGER NOT NULL,
              speedAt3000rpm REAL NOT NULL,
              kFactor REAL NOT NULL,
              timestamp INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workshop_settings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL DEFAULT '',
              phone TEXT NOT NULL DEFAULT '',
              website TEXT NOT NULL DEFAULT '',
              customText TEXT NOT NULL DEFAULT '',
              logoPath TEXT
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE runs ADD COLUMN synced INTEGER NOT NULL DEFAULT 0'
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE cars ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0'
          );
          await db.execute(
            'ALTER TABLE workshop_settings ADD COLUMN user_id INTEGER NOT NULL DEFAULT 0'
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE workshop_settings ADD COLUMN chartMinX REAL NOT NULL DEFAULT 1000.0'
          );
          await db.execute(
            'ALTER TABLE workshop_settings ADD COLUMN chartMaxX REAL NOT NULL DEFAULT 6000.0'
          );
        }
        if (oldVersion < 7) {
          // Temperatura i ciśnienie zapisywane przy pomiarze
          // NULL = brak danych (starsze przebiegi)
          await db.execute(
            'ALTER TABLE runs ADD COLUMN tempC REAL'
          );
          await db.execute(
            'ALTER TABLE runs ADD COLUMN pressureHpa REAL'
          );
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE cars (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        licensePlate TEXT,
        weightKg REAL NOT NULL,
        area REAL NOT NULL,
        cd REAL NOT NULL,
        lossDrivetrain REAL NOT NULL,
        transmission INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        carId INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        maxEngineHp REAL NOT NULL,
        maxEngineTorque REAL NOT NULL,
        sessionWeightKg REAL NOT NULL,
        correctionFactor REAL NOT NULL,
        graphDataPoints TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        tempC REAL,
        pressureHpa REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE calibrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        carId INTEGER NOT NULL,
        speedAt3000rpm REAL NOT NULL,
        kFactor REAL NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workshop_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        website TEXT NOT NULL DEFAULT '',
        customText TEXT NOT NULL DEFAULT '',
        logoPath TEXT,
        chartMinX REAL NOT NULL DEFAULT 1000.0,
        chartMaxX REAL NOT NULL DEFAULT 6000.0
      )
    ''');
  }

  Database get db {
    if (_db == null) throw Exception('Baza danych nie zainicjalizowana!');
    return _db!;
  }

  // ── CARS ──────────────────────────────────────────────────────
  Future<List<CarProfile>> getAllCars() async {
    final maps = await db.query(
      'cars',
      where: 'user_id = ?',
      whereArgs: [_userId],
    );
    return maps.map(CarProfile.fromMap).toList();
  }

  Future<int> saveCar(CarProfile car) async {
    final map = car.toMap();
    map['user_id'] = _userId;
    if (car.id == 0) {
      return db.insert('cars', map);
    } else {
      await db.update('cars', map,
          where: 'id = ? AND user_id = ?',
          whereArgs: [car.id, _userId]);
      return car.id;
    }
  }

  Future<void> deleteCar(int id) async {
    await db.delete('cars',
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, _userId]);
    await db.delete('runs', where: 'carId = ?', whereArgs: [id]);
    await db.delete('calibrations', where: 'carId = ?', whereArgs: [id]);
  }

  // ── RUNS ──────────────────────────────────────────────────────
  Future<void> saveRun(DynoRun run) async {
    await db.insert('runs', run.toMap());
  }

  Future<void> markRunSynced(int runId) async {
    await db.update('runs', {'synced': 1},
        where: 'id = ?', whereArgs: [runId]);
  }

  Future<List<DynoRun>> getUnsyncedRuns() async {
    final cars = await getAllCars();
    if (cars.isEmpty) return [];
    final carIds = cars.map((c) => c.id).toList();
    final placeholders = carIds.map((_) => '?').join(',');
    final maps = await db.query(
      'runs',
      where: 'synced = 0 AND carId IN ($placeholders)',
      whereArgs: carIds,
      orderBy: 'timestamp ASC',
    );
    return maps.map(DynoRun.fromMap).toList();
  }

  Future<List<DynoRun>> getRunsForCar(int carId) async {
    final maps = await db.query(
      'runs',
      where: 'carId = ?',
      whereArgs: [carId],
      orderBy: 'timestamp DESC',
    );
    return maps.map(DynoRun.fromMap).toList();
  }

  // ── CALIBRATIONS ──────────────────────────────────────────────
  Future<void> saveCalibration(int carId, double speedAt3000rpm) async {
    final kFactor = speedAt3000rpm > 0 ? 3000.0 / speedAt3000rpm : 0.0;
    await db.insert('calibrations', {
      'carId':          carId,
      'speedAt3000rpm': speedAt3000rpm,
      'kFactor':        kFactor,
      'timestamp':      DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, double>?> getLatestCalibration(int carId) async {
    final maps = await db.query(
      'calibrations',
      where: 'carId = ?',
      whereArgs: [carId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return {
      'speedAt3000rpm': maps.first['speedAt3000rpm'] as double,
      'kFactor':        maps.first['kFactor'] as double,
    };
  }

  // ── WORKSHOP SETTINGS ─────────────────────────────────────────
  Future<WorkshopSettings> getWorkshopSettings() async {
    final maps = await db.query(
      'workshop_settings',
      where: 'user_id = ?',
      whereArgs: [_userId],
      limit: 1,
    );
    if (maps.isEmpty) return WorkshopSettings();
    return WorkshopSettings.fromMap(maps.first);
  }

  Future<void> saveWorkshopSettings(WorkshopSettings settings) async {
    final existing = await db.query(
      'workshop_settings',
      where: 'user_id = ?',
      whereArgs: [_userId],
      limit: 1,
    );
    final map = settings.toMap();
    map['user_id'] = _userId;
    if (existing.isEmpty) {
      await db.insert('workshop_settings', map);
    } else {
      await db.update('workshop_settings', map,
          where: 'user_id = ?', whereArgs: [_userId]);
    }
  }
}