import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../main.dart';

enum MeasurementState { idle, accelerating, coasting, finished }

class DynoScreen extends StatefulWidget {
  const DynoScreen({super.key});

  @override
  State<DynoScreen> createState() => _DynoScreenState();
}

class _DynoScreenState extends State<DynoScreen> {
  MeasurementState _state = MeasurementState.idle;
  CarProfile? _activeCar;
  Timer? _simulationTimer;

  // Live Data
  double _currentSpeed = 0.0;
  double _currentHp = 0.0; // Używana do pokazywania mocy na żywo
  double _maxEngineHp = 0.0;
  double _lastSpeed = 0.0;
  double _lastSmoothedHp = 0.0; 
  DateTime? _lastTime;

  // Wybieg (Losses)
  double _coastingTimeElapsed = 0.0;
  final double _maxCoastingTime = 10.0; 

  // Listy punktów - zmienione na 'final' zgodnie z zaleceniem Fluttera
  List<FlSpot> _engineHpSpots = [];
  final List<List<double>> _rawLossPoints = [];

  // Weathercf (na razie 1.0 do symulacji)
  double sessionWeatherCf = 1.0;

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
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _startMeasurement() {
    if (_activeCar == null) return;
    
    setState(() {
      _state = MeasurementState.accelerating;
      _coastingTimeElapsed = 0.0;
      _currentSpeed = 40.0; 
      _lastSpeed = 40.0;
      _currentHp = 0.0;
      _maxEngineHp = 0.0;
      _lastSmoothedHp = 0.0;
      _engineHpSpots.clear();
      _rawLossPoints.clear();
      _lastTime = DateTime.now();
    });

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      DateTime now = DateTime.now();
      double timeDelta = now.difference(_lastTime!).inMilliseconds / 1000.0;
      double newSpeed = _currentSpeed;

      // --- FAZA A: PRZYSPIESZANIE (Moc Silnika) ---
      if (_state == MeasurementState.accelerating) {
        newSpeed += (170 - _currentSpeed) * 0.05; 
        
        if (newSpeed >= 140.0) {
          setState(() => _state = MeasurementState.coasting);
        } else {
          double hpEng = PhysicsEngine.calculateEngineHp(
            v1KmH: _lastSpeed,
            v2KmH: newSpeed,
            timeDelta: timeDelta,
            weight: _activeCar!.weightKg,
            cd: _activeCar!.cd,
            area: _activeCar!.area,
            drivetrainLossFactor: _activeCar!.lossDrivetrain, 
            lastSmoothedHp: _lastSmoothedHp,
            smoothedHpFactor: 0.3, 
          );
          
          setState(() {
            _currentHp = hpEng;
            _lastSmoothedHp = hpEng;
            if (hpEng > _maxEngineHp) _maxEngineHp = hpEng;
            
            if (newSpeed > 50 && hpEng > 10) {
              _engineHpSpots.add(FlSpot(newSpeed, hpEng));
            }
          });
        }
      } 
      // --- FAZA B: WYBIEG (Liczenie strat) ---
      else if (_state == MeasurementState.coasting) {
        newSpeed -= 0.6; 
        _coastingTimeElapsed += timeDelta;

        // POPRAWIONE: Usunięto 'dinCorrection' stąd!
        double lossHp = PhysicsEngine.calculateEngineHp(
          v1KmH: newSpeed, 
          v2KmH: _lastSpeed,
          timeDelta: timeDelta,
          weight: _activeCar!.weightKg,
          cd: _activeCar!.cd,
          area: _activeCar!.area,
          drivetrainLossFactor: 0, 
        );

        setState(() {
          _currentHp = lossHp; 
          _rawLossPoints.add([newSpeed, lossHp]);
        });

        if (_coastingTimeElapsed >= _maxCoastingTime || newSpeed <= 0) {
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

  Future<void> _stopAndSaveRun() async {
    _simulationTimer?.cancel();
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
      
      double finalHp = (smoothedWheelHp + calculatedLossAtSpeed);
      finalHp *= sessionWeatherCf; 

      correctedSpots.add(FlSpot(speed, finalHp));
      graphStringData.add('${speed.toStringAsFixed(1)};${finalHp.toStringAsFixed(1)}');
      
      if (finalHp > finalMaxHp) finalMaxHp = finalHp;
    }

    final newRun = DynoRun(
      carId: _activeCar!.id,
      timestamp: DateTime.now(),
      maxEngineHp: finalMaxHp,
      maxEngineTorque: 0,
      sessionWeightKg: _activeCar!.weightKg,
      correctionFactor: sessionWeatherCf,
      graphDataPoints: graphStringData,
    );

    await dbService.saveRun(newRun);

    // POPRAWIONE: Sprawdzenie 'mounted' przed użyciem BuildContext po await
    if (!mounted) return;

    setState(() {
      _engineHpSpots = correctedSpots;
      _maxEngineHp = finalMaxHp;
      _currentHp = 0; 
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pomiar zapisany do bazy!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeCar == null) {
      return const Center(child: Text("Brak wybranego auta", style: TextStyle(color: Colors.white)));
    }

    String statusText = "GOTOWY DO STARTU";
    Color statusColor = Colors.grey;
    if (_state == MeasurementState.accelerating) {
      statusText = "PRZYSPIESZANIE (Moc Silnika)";
      statusColor = Colors.greenAccent;
    } else if (_state == MeasurementState.coasting) {
      statusText = "WYBIEG: PROSZĘ NIE HAMOWAĆ!";
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.finished) {
      statusText = "POMIAR ZAKOŃCZONY - ZAPISANO";
      statusColor = Colors.redAccent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomiar Dyno', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Panel statusu (POPRAWIONE: withValues(alpha: ...))
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
                        backgroundColor: Colors.grey[800], color: Colors.orangeAccent, minHeight: 8,
                      ),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Zegary (POPRAWIONE: Wyświetlamy _currentHp)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(_currentSpeed.toStringAsFixed(1), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                    const Text('km/h', style: TextStyle(color: Colors.grey)),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      _state == MeasurementState.finished ? _maxEngineHp.toStringAsFixed(1) : _currentHp.toStringAsFixed(1), 
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: statusColor)
                    ),
                    Text(_state == MeasurementState.finished ? 'MAX KM' : 'Aktualnie KM', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 30),

            // WYKRES MOCY SILNIKA
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(right: 20, top: 20),
                decoration: BoxDecoration(color: Colors.grey[950], borderRadius: BorderRadius.circular(16)),
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
                        // POPRAWIONE: withValues(alpha: ...)
                        belowBarData: BarAreaData(show: true, color: Colors.greenAccent.withValues(alpha: 0.05)), 
                      ),
                    ],
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text('Prędkość (km/h)', style: TextStyle(color: Colors.grey)),
                        sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: Colors.grey, fontSize: 12))),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Przycisk Start/Stop
            GestureDetector(
              onTap: _state == MeasurementState.accelerating || _state == MeasurementState.coasting ? null : _startMeasurement,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // POPRAWIONE: withValues(alpha: ...)
                  color: _state == MeasurementState.idle || _state == MeasurementState.finished ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  border: Border.all(color: _state == MeasurementState.idle || _state == MeasurementState.finished ? Colors.greenAccent : Colors.redAccent, width: 4),
                ),
                child: Center(
                  child: Icon(
                    _state == MeasurementState.idle || _state == MeasurementState.finished ? Icons.play_arrow : Icons.save_outlined, 
                    color: _state == MeasurementState.idle || _state == MeasurementState.finished ? Colors.greenAccent : Colors.redAccent,
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