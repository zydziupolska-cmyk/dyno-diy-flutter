import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../main.dart';

enum MeasurementState { idle, accelerating, coasting, finished }

class DynoScreen extends StatefulWidget {
  final CarProfile car;
  final double? overrideWeight;
  final double weatherCf;
  final double? kFactor;
  const DynoScreen({super.key, required this.car, this.overrideWeight, this.weatherCf = 1.0, this.kFactor});

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
  double _lastSmoothedHp   = 0.0;
  double _lastSmoothedLoss = 0.0;
  DateTime? _lastTime;

  // Wybieg
  double _coastingTimeElapsed = 0.0;
  final double _maxCoastingTime = 15.0;

  // Detekcja końca przyspieszania
  // Zliczamy ile próbek z rzędu prędkość nie rośnie
  int _notAcceleratingCount = 0;
  static const int _notAcceleratingThreshold = 20; // ~2s przy 10Hz

  List<FlSpot> _engineHpSpots = [];
  final List<List<double>> _rawLossPoints = [];
  double get sessionWeatherCf => widget.weatherCf;

  @override
  void initState() {
    super.initState();
    _activeCar = widget.car;
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
      _lastSmoothedHp   = 0.0;
      _lastSmoothedLoss = 0.0;
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

      // Walidacja GPS: odrzuć nierealne skoki prędkości
      // Max przyspieszenie ~10 m/s² = 36 km/h/s
      if (_lastSpeed > 0 && timeDelta > 0) {
        final maxDelta = 36.0 * timeDelta; // max zmiana km/h w tej próbce
        if ((newSpeed - _lastSpeed).abs() > maxDelta) {
          // GPS szum - pomiń tę próbkę, tylko zaktualizuj czas
          setState(() { _lastTime = now; });
          return;
        }
      }

      // --- FAZA A: PRZYSPIESZANIE ---
      if (_state == MeasurementState.accelerating) {

        // Zliczaj ile próbek z rzędu prędkość nie rośnie
        if (newSpeed <= _lastSpeed + 0.5) {
          _notAcceleratingCount++;
        } else {
          _notAcceleratingCount = 0; // Reset gdy przyspiesza
        }

        // Detekcja końca przyspieszania:
        // - Prędkość wyraźnie spada (> 5 km/h) – zjazd z gazu lub sprzęgło
        // - LUB bieg neutralny (prędkość < 15 km/h gdy jechał > 40)
        // - LUB brak przyspieszania przez ~2s (20 próbek przy 10Hz)
        bool velocityDrop = newSpeed < _lastSpeed - 5.0;
        bool stalledOrNeutral = newSpeed < 15.0 && _lastSpeed > 40.0;
        bool prolongedNoAccel = _notAcceleratingCount >= 20 && newSpeed > 50.0;

        if (velocityDrop || stalledOrNeutral || prolongedNoAccel) {
          debugPrint('[DYNO] Koniec przyspieszania -> WYBIEG (drop=$velocityDrop neutral=$stalledOrNeutral noAccel=$prolongedNoAccel)');
          setState(() {
            _state = MeasurementState.coasting;
            _notAcceleratingCount = 0;
          });
        } else {
          // Liczymy moc gdy prędkość rośnie
          if (newSpeed > _lastSpeed + 0.1) {
            // Moc na kołach: tylko masa × przyspieszenie × prędkość
            // (jak Dynomet – opory wychodzą z wybiegu, nie z Cd/area)
            final hpWheel = PhysicsEngine.calculateWheelHp(
              v1KmH: _lastSpeed,
              v2KmH: newSpeed,
              timeDelta: timeDelta,
              weight: widget.overrideWeight ?? _activeCar!.weightKg,
            );

            // Wygładzanie EMA (alpha=0.3)
            final hpEng = PhysicsEngine.ema(hpWheel, _lastSmoothedHp, 0.55);

            setState(() {
              _currentHp     = hpEng;
              _lastSmoothedHp = hpEng;
              if (hpEng > _maxEngineHp) _maxEngineHp = hpEng;

              // Nm live (orientacyjne — finalne Nm obliczamy po wybiegu)
              if (widget.kFactor != null && widget.kFactor! > 0) {
                final rpm = newSpeed * widget.kFactor!;
                if (rpm > 0) {
                  final nm = (hpEng * 9550.0) / rpm;
                  _currentNm = nm;
                  if (nm > _maxEngineNm) _maxEngineNm = nm;
                }
              }

              // Oś X: RPM jeśli mamy kFactor, w przeciwnym razie km/h
              final xVal = (widget.kFactor != null && widget.kFactor! > 0)
                  ? newSpeed * widget.kFactor!
                  : newSpeed;
              final lastX = _engineHpSpots.isNotEmpty ? _engineHpSpots.last.x : 0.0;
              final minXStep = widget.kFactor != null ? 20.0 : 0.5;
              if (newSpeed > 30 && hpEng > 10 && xVal >= lastX + minXStep) {
                _engineHpSpots.add(FlSpot(xVal, hpEng));
              }
            });
          }
        }
      }

      // --- FAZA B: WYBIEG ---
      else if (_state == MeasurementState.coasting) {
        _coastingTimeElapsed += timeDelta;

        // Walidacja GPS - odrzuć nierealne skoki podczas wybiegu
        // Max opóźnienie bez hamulca: ~5 m/s² = 18 km/h/s
        if (_lastSpeed > 0 && timeDelta > 0) {
          final maxCoastDelta = 18.0 * timeDelta;
          if ((_lastSpeed - newSpeed).abs() > maxCoastDelta) {
            setState(() { _lastTime = now; });
            return;
          }
        }

        // Straty wybiegu: masa × opóźnienie × prędkość
        final lossRaw = PhysicsEngine.calculateCoastLossHp(
          v1KmH: _lastSpeed,
          v2KmH: newSpeed,
          timeDelta: timeDelta,
          weight: widget.overrideWeight ?? _activeCar!.weightKg,
        );

        // EMA wygładzanie strat (alpha=0.6 - mocne, GPS szum duży przy małym opóźnieniu)
        final lossHp = PhysicsEngine.ema(lossRaw, _lastSmoothedLoss, 0.60);
        _lastSmoothedLoss = lossHp;

        if (lossHp > 0 && lossHp < 200) {
          // Zapisuj tylko sensowne wartości strat (< 200 KM to górny limit)
          setState(() {
            _currentHp = lossHp;
            _rawLossPoints.add([newSpeed, lossHp]);
          });
        }

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
    double finalMaxNm = 0.0;

    for (var wheelSpot in _engineHpSpots) {
      double speed = wheelSpot.x;
      double smoothedWheelHp = wheelSpot.y;
      // Straty muszą być dodatnie - opory zawsze pochłaniają energię
      final lossAtSpeed = (a * speed + b).clamp(0.0, 500.0);
      double finalHp = (smoothedWheelHp + lossAtSpeed) * sessionWeatherCf;

      // Oblicz Nm po korekcji (z kFactor jeśli dostępny)
      // speed tutaj to wartość X z wykresu (RPM lub km/h)
      double finalNm = 0.0;
      if (widget.kFactor != null && widget.kFactor! > 0) {
        // Jeśli X był RPM - używamy bezpośrednio
        // Jeśli X był km/h - przeliczamy na RPM
        final rpm = speed; // X już jest w RPM gdy kFactor != null
        if (rpm > 0) finalNm = (finalHp * 9550.0) / rpm;
      }

      // Konwertuj X z powrotem do km/h (było RPM na wykresie live)
      final speedKmh = (widget.kFactor != null && widget.kFactor! > 0)
          ? speed / widget.kFactor!
          : speed;
      correctedSpots.add(FlSpot(speedKmh, finalHp));
      // Format: speed_kmh;hp;nm
      graphStringData.add('${speedKmh.toStringAsFixed(1)};${finalHp.toStringAsFixed(1)};${finalNm.toStringAsFixed(1)}');

      if (finalHp > finalMaxHp) finalMaxHp = finalHp;
      if (finalNm > finalMaxNm) finalMaxNm = finalNm;
    }

    final newRun = DynoRun(
      carId: _activeCar!.id,
      timestamp: DateTime.now(),
      maxEngineHp: finalMaxHp,
      maxEngineTorque: finalMaxNm, // Nm po korekcji DIN i stratach
      sessionWeightKg: widget.overrideWeight ?? _activeCar!.weightKg,
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

            // Zegary - wiersz 1: prędkość
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(_currentSpeed.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold)),
                    const Text('km/h', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Zegary - wiersz 2: KM i Nm
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      _state == MeasurementState.finished
                          ? _maxEngineHp.toStringAsFixed(1)
                          : _currentHp.toStringAsFixed(1),
                      style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold,
                          color: statusColor),
                    ),
                    Text(
                      _state == MeasurementState.finished ? 'MAX KM' : 'KM',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
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
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold,
                            color: Colors.blueAccent),
                      ),
                      Text(
                        _state == MeasurementState.finished ? 'MAX Nm' : 'Nm',
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
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
                        axisNameWidget: Text(widget.kFactor != null ? 'RPM' : 'km/h',
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