import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/car_profile.dart';
import '../models/workshop_settings.dart';

class DatabaseService {
  Database? _db;

  Future<void> init() async {
    final path = join(await getDatabasesPath(), 'dyno_diy.db');
    _db = await openDatabase(
      path,
      version: 4,
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
          // Dodaj kolumnę synced — 0 = nie zsync, 1 = zsync z chmurą
          // Wszystkie istniejące pomiary dostają 0 (niezsynkowane)
          await db.execute(
            'ALTER TABLE runs ADD COLUMN synced INTEGER NOT NULL DEFAULT 0'
          );
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE cars (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        synced INTEGER NOT NULL DEFAULT 0
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
        name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        website TEXT NOT NULL DEFAULT '',
        customText TEXT NOT NULL DEFAULT '',
        logoPath TEXT
      )
    ''');
  }

  Database get db {
    if (_db == null) throw Exception('Baza danych nie zainicjalizowana!');
    return _db!;
  }

  // --- CARS ---
  Future<List<CarProfile>> getAllCars() async {
    final maps = await db.query('cars');
    return maps.map(CarProfile.fromMap).toList();
  }

  Future<int> saveCar(CarProfile car) async {
    if (car.id == 0) {
      return await db.insert('cars', car.toMap());
    } else {
      await db.update('cars', car.toMap(), where: 'id = ?', whereArgs: [car.id]);
      return car.id;
    }
  }

  Future<void> deleteCar(int id) async {
    await db.delete('cars', where: 'id = ?', whereArgs: [id]);
    await db.delete('runs', where: 'carId = ?', whereArgs: [id]);
    await db.delete('calibrations', where: 'carId = ?', whereArgs: [id]);
  }

  // --- RUNS ---
  Future<void> saveRun(DynoRun run) async {
    await db.insert('runs', run.toMap());
  }

  Future<void> markRunSynced(int runId) async {
    await db.update(
      'runs',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  /// Zwraca wszystkie pomiary które nie zostały jeszcze zsynchronizowane
  Future<List<DynoRun>> getUnsyncedRuns() async {
    final maps = await db.query(
      'runs',
      where: 'synced = 0',
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

  // --- CALIBRATIONS ---
  Future<void> saveCalibration(int carId, double speedAt3000rpm) async {
    final kFactor = 3000.0 / speedAt3000rpm;
    await db.insert('calibrations', {
      'carId': carId,
      'speedAt3000rpm': speedAt3000rpm,
      'kFactor': kFactor,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
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
      'kFactor': maps.first['kFactor'] as double,
    };
  }

  // --- WORKSHOP SETTINGS ---
  Future<WorkshopSettings> getWorkshopSettings() async {
    final maps = await db.query('workshop_settings', limit: 1);
    if (maps.isEmpty) return WorkshopSettings();
    return WorkshopSettings.fromMap(maps.first);
  }

  Future<void> saveWorkshopSettings(WorkshopSettings settings) async {
    final existing = await db.query('workshop_settings', limit: 1);
    if (existing.isEmpty) {
      await db.insert('workshop_settings', settings.toMap());
    } else {
      await db.update(
        'workshop_settings',
        settings.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }
}