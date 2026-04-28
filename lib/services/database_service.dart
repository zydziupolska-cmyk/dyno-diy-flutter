import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/car_profile.dart';

class DatabaseService {
  late Isar isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    // DODAJ DynoRunSchema TUTAJ!
    isar = await Isar.open(
      [CarProfileSchema, DynoRunSchema], // <--- Dodane!
      directory: dir.path,
    );
  }

  // --- CARS ---
  Future<List<CarProfile>> getAllCars() async => await isar.carProfiles.where().findAll();
  Future<void> saveCar(CarProfile car) async => await isar.writeTxn(() => isar.carProfiles.put(car));
  Future<void> deleteCar(int id) async => await isar.writeTxn(() => isar.carProfiles.delete(id));

  // --- DYNO RUNS --- (NOWE FUNKCJE)
  Future<void> saveRun(DynoRun run) async {
    await isar.writeTxn(() => isar.dynoRuns.put(run));
  }

  // Pobierz pomiary dla konkretnego auta
  Future<List<DynoRun>> getRunsForCar(int carId) async {
    return await isar.dynoRuns.filter().carIdEqualTo(carId).sortByTimestampDesc().findAll();
  }
}