// Model danych – bez Isar, czyste Dart klasy

enum TransmissionType { manual, automatic, awdManual, awdAutomatic }

class CarProfile {
  final int id;
  final String name;
  final String? licensePlate;
  final double weightKg;
  final double area;
  final double cd;
  final double lossDrivetrain;
  final TransmissionType transmission;

  CarProfile({
    this.id = 0,
    required this.name,
    this.licensePlate,
    required this.weightKg,
    required this.area,
    required this.cd,
    required this.lossDrivetrain,
    required this.transmission,
  });

  Map<String, dynamic> toMap() => {
    'id': id == 0 ? null : id,
    'name': name,
    'licensePlate': licensePlate,
    'weightKg': weightKg,
    'area': area,
    'cd': cd,
    'lossDrivetrain': lossDrivetrain,
    'transmission': transmission.index,
  };

  factory CarProfile.fromMap(Map<String, dynamic> m) => CarProfile(
    id: m['id'] as int,
    name: m['name'] as String,
    licensePlate: m['licensePlate'] as String?,
    weightKg: m['weightKg'] as double,
    area: m['area'] as double,
    cd: m['cd'] as double,
    lossDrivetrain: m['lossDrivetrain'] as double,
    transmission: TransmissionType.values[m['transmission'] as int],
  );
}

class DynoRun {
  final int id;
  final int carId;
  final DateTime timestamp;
  final double maxEngineHp;
  final double maxEngineTorque;
  final double sessionWeightKg;
  final double correctionFactor;
  final List<String> graphDataPoints;

  DynoRun({
    this.id = 0,
    required this.carId,
    required this.timestamp,
    required this.maxEngineHp,
    required this.maxEngineTorque,
    required this.sessionWeightKg,
    required this.correctionFactor,
    required this.graphDataPoints,
  });

  Map<String, dynamic> toMap() => {
    'id': id == 0 ? null : id,
    'carId': carId,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'maxEngineHp': maxEngineHp,
    'maxEngineTorque': maxEngineTorque,
    'sessionWeightKg': sessionWeightKg,
    'correctionFactor': correctionFactor,
    'graphDataPoints': graphDataPoints.join('|'),
  };

  factory DynoRun.fromMap(Map<String, dynamic> m) => DynoRun(
    id: m['id'] as int,
    carId: m['carId'] as int,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    maxEngineHp: m['maxEngineHp'] as double,
    maxEngineTorque: m['maxEngineTorque'] as double,
    sessionWeightKg: m['sessionWeightKg'] as double,
    correctionFactor: m['correctionFactor'] as double,
    graphDataPoints: (m['graphDataPoints'] as String).split('|'),
  );
}