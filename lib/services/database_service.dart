import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/car_profile.dart';

class DatabaseService {
  Database? _db;

  Future<void> init() async {
    final path = join(await getDatabasesPath(), 'dyno_diy.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
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
            graphDataPoints TEXT NOT NULL
          )
        ''');
      },
    );
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
  }

  // --- RUNS ---
  Future<void> saveRun(DynoRun run) async {
    await db.insert('runs', run.toMap());
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
}