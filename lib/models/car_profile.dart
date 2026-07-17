// Model danych – bez Isar, czyste Dart klasy

enum TransmissionType { manual, automatic, awdManual, awdAutomatic }

class CarProfile {
  final int    id;
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
    'id':            id == 0 ? null : id,
    'name':          name,
    'licensePlate':  licensePlate,
    'weightKg':      weightKg,
    'area':          area,
    'cd':            cd,
    'lossDrivetrain':lossDrivetrain,
    'transmission':  transmission.index,
  };

  factory CarProfile.fromMap(Map<String, dynamic> m) => CarProfile(
    id:            m['id']             as int,
    name:          m['name']           as String,
    licensePlate:  m['licensePlate']   as String?,
    weightKg:      m['weightKg']       as double,
    area:          m['area']           as double,
    cd:            m['cd']             as double,
    lossDrivetrain:m['lossDrivetrain'] as double,
    transmission:  TransmissionType.values[m['transmission'] as int],
  );
}

class DynoRun {
  final int      id;
  final int      carId;
  final DateTime timestamp;
  final double   maxEngineHp;
  final double   maxEngineTorque;
  final double   sessionWeightKg;
  final double   correctionFactor;
  final List<String> graphDataPoints;
  final bool     synced;
  final double?  tempC;        // temperatura powietrza [°C] — może być null (starsze przebiegi)
  final double?  pressureHpa;  // ciśnienie atmosferyczne [hPa] — może być null

  DynoRun({
    this.id = 0,
    required this.carId,
    required this.timestamp,
    required this.maxEngineHp,
    required this.maxEngineTorque,
    required this.sessionWeightKg,
    required this.correctionFactor,
    required this.graphDataPoints,
    this.synced      = false,
    this.tempC,
    this.pressureHpa,
  });

  Map<String, dynamic> toMap() => {
    'id':              id == 0 ? null : id,
    'carId':           carId,
    'timestamp':       timestamp.millisecondsSinceEpoch,
    'maxEngineHp':     maxEngineHp,
    'maxEngineTorque': maxEngineTorque,
    'sessionWeightKg': sessionWeightKg,
    'correctionFactor':correctionFactor,
    'graphDataPoints': graphDataPoints.join('|'),
    'synced':          synced ? 1 : 0,
    'tempC':           tempC,
    'pressureHpa':     pressureHpa,
  };

  factory DynoRun.fromMap(Map<String, dynamic> m) => DynoRun(
    id:               m['id']               as int,
    carId:            m['carId']            as int,
    timestamp:        DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
    maxEngineHp:      (m['maxEngineHp']      as num).toDouble(),
    maxEngineTorque:  (m['maxEngineTorque']  as num).toDouble(),
    sessionWeightKg:  (m['sessionWeightKg']  as num).toDouble(),
    correctionFactor: (m['correctionFactor'] as num).toDouble(),
    graphDataPoints:  (m['graphDataPoints']  as String).split('|'),
    synced:           (m['synced']           as int? ?? 0) == 1,
    tempC:            (m['tempC']            as num?)?.toDouble(),
    pressureHpa:      (m['pressureHpa']      as num?)?.toDouble(),
  );
}