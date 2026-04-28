import 'package:isar/isar.dart';

part 'car_profile.g.dart';

@collection
class CarProfile {
  Id id = Isar.autoIncrement;

  String name;
  String? licensePlate;
  
  double weightKg;
  double area;
  double cd;
  double lossDrivetrain;

  @enumerated
  TransmissionType transmission;

  CarProfile({
    required this.name,
    this.licensePlate,
    required this.weightKg,
    required this.area,
    required this.cd,
    required this.lossDrivetrain,
    required this.transmission,
  });
}

enum TransmissionType { manual, automatic, awdManual, awdAutomatic }

// ---------------------------------------------------------
// NOWY MODEL DLA ZAPISANYCH POMIARÓW
// ---------------------------------------------------------
@collection
class DynoRun {
  Id id = Isar.autoIncrement;

  // Powiązanie z autem (np. id BMW E46)
  int carId;
  DateTime timestamp;

  // Główne wyniki
  double maxEngineHp;
  double maxEngineTorque; // Na razie nie liczymy, ale zostawiamy miejsce

  // Warunki sesji
  double sessionWeightKg;
  double correctionFactor; // DIN cf

  // SUROWE DANE DO WYKRESU (zapisane jako lista stringów "speed;hp")
  List<String> graphDataPoints;

  DynoRun({
    required this.carId,
    required this.timestamp,
    required this.maxEngineHp,
    required this.maxEngineTorque,
    required this.sessionWeightKg,
    required this.correctionFactor,
    required this.graphDataPoints,
  });
}