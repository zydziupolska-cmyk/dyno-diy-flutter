import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../main.dart';

enum MeasurementState { idle, accelerating, coasting, finished }

class DynoScreen extends StatefulWidget {
  final double? overrideWeight;
  final double weatherCf;
  final double? kFactor;
  const DynoScreen({super.key, this.overrideWeight, this.weatherCf = 1.0, this.kFactor});

  @override
  State<DynoScreen> createState() => _DynoScreenState();
}

class _DynoScreenState extends State<DynoScreen> {
  MeasurementState _state = MeasurementState.idle;
  CarProfile? _activeCar;
  StreamSubscription<double>? _speedSubscription;

  // Live Data
  double _currentSpeed = 0.0;
  double _currentHp = 0.0;
  double _currentNm = 0.0;
  double _maxEngineNm = 0.0;
  double _maxEngineHp = 0.0;
  double _lastSpeed = 0.0;
  double _lastSmoothedHp = 0.0;
  DateTime? _lastTime;

  // Wybieg
  double _coastingTimeElapsed = 0.0;
  final double _maxCoastingTime = 15.0;

  // Detekcja końca przyspieszania
  // Zliczamy ile próbek z rzędu prędkość nie rośnie
  int _notAcceleratingCount = 0;
  static const int _notAcceleratingThreshold = 8; // ~800ms przy 10Hz

  List<FlSpot> _engineHpSpots = [];
  final List<List<double>> _rawLossPoints = [];
  double get sessionWeatherCf => widget.weatherCf;

  @override
  void initState() {
    super.initState();
    _loadActiveCar();
  }

  Future<void> _loadActiveCar() async {
    final cars = await dbService.getAllCars();
    if (cars.isNotEmpty) {
      setState(() { _activeCar = cars.first; });
    }
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    super.dispose();
  }

  void _startMeasurement() {
    if (_activeCar == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak wybranego pojazdu')),
      );
      return;
    }
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ESP32 nie jest połączony')),
      );
      return;
    }

    setState(() {
      _state = MeasurementState.accelerating;
      _coastingTimeElapsed = 0.0;
      _currentSpeed = 0.0;
      _lastSpeed = 0.0;
      _currentHp = 0.0;
      _currentNm = 0.0;
      _maxEngineNm = 0.0;
      _maxEngineHp = 0.0;
      _lastSmoothedHp = 0.0;
      _notAcceleratingCount = 0;
      _engineHpSpots.clear();
      _rawLossPoints.clear();
      _lastTime = DateTime.now();
    });

    _speedSubscription = btService.speedStream.listen((gpsSpeed) {
      if (_state == MeasurementState.idle || _state == MeasurementState.finished) return;

      DateTime now = DateTime.now();
      double timeDelta = now.difference(_lastTime!).inMilliseconds / 1000.0;
      if (timeDelta < 0.02) return;

      double newSpeed = gpsSpeed;

      // --- FAZA A: PRZYSPIESZANIE ---
      if (_state == MeasurementState.accelerating) {

        // Zliczaj ile próbek z rzędu prędkość nie rośnie (lub spada)
        if (newSpeed <= _lastSpeed + 0.3) {
          _notAcceleratingCount++;
        } else {
          _notAcceleratingCount = 0; // Reset gdy przyspiesza
        }

        // Detekcja końca przyspieszania:
        // - Przez _notAcceleratingThreshold próbek nie przyspiesza
        // - LUB prędkość wyraźnie spada (> 3 km/h) – zjazd z gazu
        // - LUB prędkość poniżej 20 km/h (bieg neutralny / sprzęgło)
        bool velocityDrop = newSpeed < _lastSpeed - 3.0;
        bool stalledOrNeutral = newSpeed < 20.0 && _lastSpeed > 30.0;
        bool prolongedNoAccel = _notAcceleratingCount >= _notAcceleratingThreshold && newSpeed > 40.0;

        if (velocityDrop || stalledOrNeutral || prolongedNoAccel) {
          debugPrint('[DYNO] Koniec przyspieszania -> WYBIEG (drop=$velocityDrop neutral=$stalledOrNeutral noAccel=$prolongedNoAccel)');
          setState(() {
            _state = MeasurementState.coasting;
            _notAcceleratingCount = 0;
          });
        } else {
          // Liczymy moc gdy prędkość rośnie
          if (newSpeed > _lastSpeed + 0.1) {
            double hpEng = PhysicsEngine.calculateEngineHp(
              v1KmH: _lastSpeed,
              v2KmH: newSpeed,
              timeDelta: timeDelta,
              weight: widget.overrideWeight ?? _activeCar!.weightKg,
              cd: _activeCar!.cd,
              area: _activeCar!.area,
              drivetrainLossFactor: _activeCar!.lossDrivetrain,
              lastSmoothedHp: _lastSmoothedHp,
              smoothedHpFactor: 0.15,
            );

            setState(() {
              _currentHp = hpEng;
              _lastSmoothedHp = hpEng;
              if (hpEng > _maxEngineHp) _maxEngineHp = hpEng;
            // Oblicz Nm z RPM (jezeli mamy kFactor z kalibracji)
            if (widget.kFactor != null && widget.kFactor! > 0) {
              final rpm = newSpeed * widget.kFactor!;
              if (rpm > 0) {
                final nm = (hpEng * 9550.0) / rpm;
                _currentNm = nm;
                if (nm > _maxEngineNm) _maxEngineNm = nm;
              }
            }
              if (newSpeed > 30 && hpEng > 10) {
                _engineHpSpots.add(FlSpot(newSpeed, hpEng));
              }
            });
          }
        }
      }

      // --- FAZA B: WYBIEG ---
      else if (_state == MeasurementState.coasting) {
        _coastingTimeElapsed += timeDelta;

        double lossHp = PhysicsEngine.calculateEngineHp(
          v1KmH: newSpeed,
          v2KmH: _lastSpeed,
          timeDelta: timeDelta,
          weight: widget.overrideWeight ?? _activeCar!.weightKg,
          cd: _activeCar!.cd,
          area: _activeCar!.area,
          drivetrainLossFactor: 0,
        );

        setState(() {
          _currentHp = lossHp;
          _rawLossPoints.add([newSpeed, lossHp]);
        });

        if (_coastingTimeElapsed >= _maxCoastingTime || newSpeed <= 30) {
          _stopAndSaveRun();
        }
      }

      setState(() {
        _currentSpeed = newSpeed;
        _lastSpeed = newSpeed;
        _lastTime = now;
      });
    });
  }

  // Ręczne przejście do wybiegu (przycisk)
  void _manualStartCoasting() {
    if (_state != MeasurementState.accelerating) return;
    debugPrint('[DYNO] Ręczny start wybiegu');
    setState(() {
      _state = MeasurementState.coasting;
      _coastingTimeElapsed = 0.0;
      _notAcceleratingCount = 0;
    });
  }

  Future<void> _stopAndSaveRun() async {
    _speedSubscription?.cancel();
    if (_activeCar == null) return;

    setState(() => _state = MeasurementState.finished);

    final lossRegression = PhysicsEngine.calculateLossRegression(_rawLossPoints);
    double a = lossRegression['a'] ?? 0;
    double b = lossRegression['b'] ?? 0;

    List<FlSpot> correctedSpots = [];
    List<String> graphStringData = [];
    double finalMaxHp = 0.0;

    for (var wheelSpot in _engineHpSpots) {
      double speed = wheelSpot.x;
      double smoothedWheelHp = wheelSpot.y;
      double calculatedLossAtSpeed = (a * speed + b);
      double finalHp = (smoothedWheelHp + calculatedLossAtSpeed) * sessionWeatherCf;

      correctedSpots.add(FlSpot(speed, finalHp));
      graphStringData.add('${speed.toStringAsFixed(1)};${finalHp.toStringAsFixed(1)}');
      if (finalHp > finalMaxHp) finalMaxHp = finalHp;
    }

    final newRun = DynoRun(
      carId: _activeCar!.id,
      timestamp: DateTime.now(),
      maxEngineHp: finalMaxHp,
      maxEngineTorque: _maxEngineNm,
      sessionWeightKg: _activeCar!.weightKg,
      correctionFactor: sessionWeatherCf,
      graphDataPoints: graphStringData,
    );

    await dbService.saveRun(newRun);
    if (!mounted) return;

    setState(() {
      _engineHpSpots = correctedSpots;
      _maxEngineHp = finalMaxHp;
      _currentHp = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pomiar zapisany! Moc max: ${finalMaxHp.toStringAsFixed(1)} KM')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCar == null) {
      return const Center(child: Text('Brak wybranego auta', style: TextStyle(color: Colors.white)));
    }

    String statusText = 'GOTOWY DO STARTU';
    Color statusColor = Colors.grey;

    if (!btService.isConnected) {
      statusText = 'CZEKAM NA ESP32...';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.accelerating) {
      statusText = 'PRZYSPIESZANIE (Moc Silnika)';
      statusColor = Colors.greenAccent;
    } else if (_state == MeasurementState.coasting) {
      statusText = 'WYBIEG: PROSZĘ NIE HAMOWAĆ!';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.finished) {
      statusText = 'POMIAR ZAKOŃCZONY - ZAPISANO';
      statusColor = Colors.redAccent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomiar Dyno', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Panel statusu
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Column(
                children: [
                  Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  if (_state == MeasurementState.coasting)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: LinearProgressIndicator(
                        value: _coastingTimeElapsed / _maxCoastingTime,
                        backgroundColor: Colors.grey[800],
                        color: Colors.orangeAccent,
                        minHeight: 8,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Zegary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(_currentSpeed.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                    const Text('km/h', style: TextStyle(color: Colors.grey)),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      _state == MeasurementState.finished
                          ? _maxEngineHp.toStringAsFixed(1)
                          : _currentHp.toStringAsFixed(1),
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                    Text(
                      _state == MeasurementState.finished ? 'MAX KM' : 'KM',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                if (widget.kFactor != null)
                  Column(
                    children: [
                      Text(
                        _state == MeasurementState.finished
                            ? _maxEngineNm.toStringAsFixed(1)
                            : _currentNm.toStringAsFixed(1),
                        style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                            color: Colors.blueAccent),
                      ),
                      Text(
                        _state == MeasurementState.finished ? 'MAX Nm' : 'Nm',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Przycisk ręcznego startu wybiegu
            if (_state == MeasurementState.accelerating)
              OutlinedButton.icon(
                onPressed: _manualStartCoasting,
                icon: const Icon(Icons.arrow_downward, color: Colors.orangeAccent),
                label: const Text('ZDJĄŁEM GAZ → START WYBIEGU',
                    style: TextStyle(color: Colors.orangeAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orangeAccent),
                ),
              ),

            const SizedBox(height: 10),

            // Wykres
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(right: 20, top: 20),
                decoration: BoxDecoration(
                    color: Colors.grey[950], borderRadius: BorderRadius.circular(16)),
                child: LineChart(
                  LineChartData(
                    minX: 40, maxX: 160, minY: 0,
                    maxY: _maxEngineHp > 200 ? _maxEngineHp + 50 : 300,
                    lineBarsData: [
                      LineChartBarData(
                        spots: _engineHpSpots,
                        isCurved: true,
                        curveSmoothness: 0.35,
                        color: Colors.greenAccent,
                        barWidth: 6,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                            show: true,
                            color: Colors.greenAccent.withValues(alpha: 0.05)),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text('Prędkość (km/h)',
                            style: TextStyle(color: Colors.grey)),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (val, meta) => Text(val.toInt().toString(),
                              style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Przycisk Start
            GestureDetector(
              onTap: (_state == MeasurementState.accelerating || _state == MeasurementState.coasting)
                  ? null
                  : _startMeasurement,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_state == MeasurementState.idle || _state == MeasurementState.finished)
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  border: Border.all(
                    color: (_state == MeasurementState.idle || _state == MeasurementState.finished)
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    width: 4,
                  ),
                ),
                child: Center(
                  child: Icon(
                    (_state == MeasurementState.idle || _state == MeasurementState.finished)
                        ? Icons.play_arrow
                        : Icons.save_outlined,
                    color: (_state == MeasurementState.idle || _state == MeasurementState.finished)
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 50,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}