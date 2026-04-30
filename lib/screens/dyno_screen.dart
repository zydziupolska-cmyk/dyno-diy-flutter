import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../main.dart';
import 'history_screen.dart';
import 'gps_replay_screen.dart';
import '../services/export_service.dart';

enum MeasurementState { idle, accelerating, coasting, finished }

class DynoScreen extends StatefulWidget {
  final CarProfile car;
  final double? overrideWeight;
  final double weatherCf;
  final double? kFactor;
  const DynoScreen({
    super.key,
    required this.car,
    this.overrideWeight,
    this.weatherCf = 1.0,
    this.kFactor,
  });

  @override
  State<DynoScreen> createState() => _DynoScreenState();
}

class _DynoScreenState extends State<DynoScreen> {
  MeasurementState _state = MeasurementState.idle;
  StreamSubscription<double>? _speedSub;

  // Live values
  double _currentSpeed = 0.0;
  double _currentHp    = 0.0;
  double _currentNm    = 0.0;
  double _maxHp        = 0.0;
  double _maxNm        = 0.0;

  // Tracking
  double    _lastSpeed        = 0.0;
  double    _lastChangedSpeed = -1.0; // ostatnia ZMIENIONA prędkość GPS
  DateTime? _lastChangedTime;          // czas ostatniej ZMIANY
  DateTime? _lastSavedTime;            // czas ostatniego ZAPISANEGO punktu
  DateTime? _lastTime;

  // Coasting timer
  double    _coastingElapsed  = 0.0;
  DateTime? _coastingStart;
  Timer?    _coastingTimer;

  // Coasting detection
  int _noAccelCount = 0;

  // Data
  final List<FlSpot>        _spots      = []; // surowe punkty (x=RPM lub km/h, y=HP_wheel)
  final List<List<double>>  _lossPoints = []; // [speed_kmh, lossHp]
  final List<GpsSample>     _allSamples = []; // wszystkie próbki GPS

  // Results
  DynoRun? _savedRun;

  double get _weight => widget.overrideWeight ?? widget.car.weightKg;
  bool   get _useRpm => widget.kFactor != null && widget.kFactor! > 0;

  @override
  void dispose() {
    _speedSub?.cancel();
    _coastingTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _currentSpeed = _currentHp = _currentNm = _maxHp = _maxNm = 0;
    _lastSpeed = _lastChangedSpeed = -1.0;
    _lastChangedTime = _lastSavedTime = _lastTime = null;
    _coastingElapsed = 0;
    _coastingStart = null;
    _coastingTimer?.cancel();
    _noAccelCount = 0;
    _spots.clear();
    _lossPoints.clear();
    _allSamples.clear();
    _savedRun = null;
  }

  void _startMeasurement() {
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ESP32 nie jest połączony!')));
      return;
    }
    setState(() {
      _reset();
      _state = MeasurementState.accelerating;
      _lastTime = DateTime.now();
    });

    _speedSub = btService.speedStream.listen(_onSpeed);
  }

  void _onSpeed(double gpsSpeed) {
    if (_state == MeasurementState.idle ||
        _state == MeasurementState.finished) return;

    final now = DateTime.now();
    final dt  = _lastTime != null
        ? now.difference(_lastTime!).inMilliseconds / 1000.0
        : 0.1;
    if (dt < 0.02) return;

    // ── Zapisz próbkę GPS do replay ─────────────────────────────────────────
    _allSamples.add(GpsSample(
      speed:    gpsSpeed,
      dt:       dt,
      rejected: false,
      reason:   '',
      phase:    _state == MeasurementState.accelerating ? 'ACC' : 'COAST',
    ));

    // ── Detekcja ZMIANY prędkości GPS ────────────────────────────────────────
    // GPS NMEA/NEO-M9N może wysyłać tę samą wartość przez kilka próbek
    // Używamy dt od ostatniej ZMIANY do prawidłowego przyspieszenia
    final speedChanged = (_lastChangedSpeed < 0) ||
        (gpsSpeed - _lastChangedSpeed).abs() > 0.01;

    // dt od ostatniej ZMIANY prędkości (prawidłowe przyspieszenie)
    // Przy pierwszej zmianie używamy dt od ostatniej próbki jako fallback
    final dtFromChange = _lastChangedTime != null
        ? now.difference(_lastChangedTime!).inMilliseconds / 1000.0
        : dt;

    if (speedChanged) {
      _lastChangedSpeed = gpsSpeed;
      _lastChangedTime  = now;
    }

    // ── PRZYSPIESZANIE ───────────────────────────────────────────────────────
    if (_state == MeasurementState.accelerating) {
      if (gpsSpeed <= _lastSpeed + 0.3) {
        _noAccelCount++;
      } else {
        _noAccelCount = 0;
      }

      final drop     = gpsSpeed < _lastSpeed - 2.0;
      final noAccel  = _noAccelCount >= 15 && gpsSpeed > 30.0;

      if (drop || noAccel) {
        _startCoasting();
      } else if (speedChanged && gpsSpeed > _lastSpeed + 0.1
                 && dtFromChange > 0.05) {
        // Oblicz moc używając dt od ostatniej ZMIANY prędkości
        final dtSaved = _lastSavedTime != null
            ? now.difference(_lastSavedTime!).inMilliseconds / 1000.0
            : dtFromChange;

        final lastSpdKmh = _spots.isNotEmpty
            ? (_useRpm ? _spots.last.x / widget.kFactor! : _spots.last.x)
            : _lastChangedSpeed;

        final hpWheel = PhysicsEngine.calculateWheelHp(
          v1KmH:     lastSpdKmh,
          v2KmH:     gpsSpeed,
          timeDelta: dtSaved.clamp(0.05, 10.0),
          weight:    _weight,
        );

        final xVal  = _useRpm ? gpsSpeed * widget.kFactor! : gpsSpeed;
        final lastX = _spots.isNotEmpty ? _spots.last.x : 0.0;
        final step  = _useRpm ? 50.0 : 1.0;

        double nmLive = 0;
        if (_useRpm) {
          final rpm = gpsSpeed * widget.kFactor!;
          if (rpm > 0) nmLive = (hpWheel * 9550.0) / rpm;
        }

        setState(() {
          _currentHp = hpWheel;
          _currentNm = nmLive;
          if (hpWheel > _maxHp) _maxHp = hpWheel;
          if (nmLive  > _maxNm) _maxNm = nmLive;

          if (gpsSpeed > 20 && hpWheel > 5 && xVal >= lastX + step) {
            _spots.add(FlSpot(xVal, hpWheel));
            _lastSavedTime = now;
          }
        });
      }
    }

    // ── WYBIEG ───────────────────────────────────────────────────────────────
    else if (_state == MeasurementState.coasting) {
      if (speedChanged && _lastSpeed > gpsSpeed && dtFromChange > 0.05) {
        final lossRaw = PhysicsEngine.calculateCoastLossHp(
          v1KmH:     _lastSpeed,
          v2KmH:     gpsSpeed,
          timeDelta: dtFromChange.clamp(0.05, 10.0),
          weight:    _weight,
        );
        if (lossRaw > 0 && lossRaw < 200) {
          setState(() {
            _currentHp = lossRaw;
            _lossPoints.add([gpsSpeed, lossRaw]);
          });
        }
      }
    }

    setState(() {
      _currentSpeed = gpsSpeed;
      _lastSpeed    = gpsSpeed;
      _lastTime     = now;
    });
  }

  void _startCoasting() {
    _coastingStart = DateTime.now();
    _coastingTimer?.cancel();
    _coastingTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted || _state != MeasurementState.coasting) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now()
          .difference(_coastingStart!)
          .inMilliseconds / 1000.0;
      setState(() => _coastingElapsed = elapsed);
      if (elapsed >= 15.0) {
        t.cancel();
        _stopAndSave();
      }
    });
    setState(() {
      _state           = MeasurementState.coasting;
      _coastingElapsed = 0.0;
      _noAccelCount    = 0;
    });
  }

  void _manualCoast() {
    if (_state != MeasurementState.accelerating) return;
    _startCoasting();
  }

  Future<void> _stopAndSave() async {
    _speedSub?.cancel();
    setState(() => _state = MeasurementState.finished);

    // Regresja strat
    final reg = PhysicsEngine.calculateLossRegression(_lossPoints);
    final a   = reg['a'] ?? 0.0;
    final b   = reg['b'] ?? 0.0;

    debugPrint('[DYNO] Strat: a=$a b=$b n=${_lossPoints.length}');

    final correctedSpots = <FlSpot>[];
    final dataPoints     = <String>[];
    double maxHp = 0, maxNm = 0;

    for (final spot in _spots) {
      final speedKmh = _useRpm ? spot.x / widget.kFactor! : spot.x;
      final hpWheel  = spot.y;
      final loss     = (a * speedKmh + b).clamp(0.0, 200.0);
      final finalHp  = (hpWheel + loss) * widget.weatherCf;

      double finalNm = 0;
      if (_useRpm) {
        final rpm = speedKmh * widget.kFactor!;
        if (rpm > 0) finalNm = (finalHp * 9550.0) / rpm;
      }

      correctedSpots.add(FlSpot(speedKmh, finalHp));
      dataPoints.add(
        '${speedKmh.toStringAsFixed(1)};'
        '${finalHp.toStringAsFixed(1)};'
        '${finalNm.toStringAsFixed(1)}'
      );
      if (finalHp > maxHp) { maxHp = finalHp; }
      if (finalNm > maxNm) { maxNm = finalNm; }
    }

    final run = DynoRun(
      carId:            widget.car.id,
      timestamp:        DateTime.now(),
      maxEngineHp:      maxHp,
      maxEngineTorque:  maxNm,
      sessionWeightKg:  _weight,
      correctionFactor: widget.weatherCf,
      graphDataPoints:  dataPoints,
    );
    await dbService.saveRun(run);
    if (!mounted) return;

    setState(() {
      _spots
        ..clear()
        ..addAll(correctedSpots);
      _maxHp    = maxHp;
      _maxNm    = maxNm;
      _savedRun = run;
    });
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Zapisano! ${maxHp.toStringAsFixed(1)} KM'
          '${maxNm > 0 ? " / ${maxNm.toStringAsFixed(1)} Nm" : ""}'),
      backgroundColor: Colors.greenAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    String statusText  = btService.isConnected ? 'GOTOWY DO STARTU' : 'CZEKAM NA ESP32...';
    Color  statusColor = btService.isConnected ? Colors.grey : Colors.orangeAccent;

    if (_state == MeasurementState.accelerating) {
      statusText  = 'PRZYSPIESZANIE';
      statusColor = Colors.greenAccent;
    } else if (_state == MeasurementState.coasting) {
      statusText  = 'WYBIEG: NIE HAMOWAĆ!';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.finished) {
      statusText  = 'ZAPISANO';
      statusColor = Colors.redAccent;
    }

    final minX = _useRpm ? 1000.0 : 20.0;
    final maxX = _useRpm ? 6500.0 : 200.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomiar Dyno',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(children: [
          // Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor),
            ),
            child: Column(children: [
              Text(statusText,
                  style: TextStyle(color: statusColor,
                      fontWeight: FontWeight.bold, fontSize: 14)),
              if (_state == MeasurementState.coasting)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: _coastingElapsed / 15.0,
                    backgroundColor: Colors.grey[800],
                    color: Colors.orangeAccent,
                    minHeight: 6,
                  ),
                ),
            ]),
          ),

          const SizedBox(height: 10),

          // Prędkość
          Text(_currentSpeed.toStringAsFixed(1),
              style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold)),
          const Text('km/h', style: TextStyle(color: Colors.grey, fontSize: 13)),

          const SizedBox(height: 8),

          // KM + Nm
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [
              Text(
                _state == MeasurementState.finished
                    ? _maxHp.toStringAsFixed(1)
                    : _currentHp.toStringAsFixed(1),
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
              Text(_state == MeasurementState.finished ? 'MAX KM' : 'KM',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            if (widget.kFactor != null)
              Column(children: [
                Text(
                  _state == MeasurementState.finished
                      ? _maxNm.toStringAsFixed(1)
                      : _currentNm.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 38,
                      fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                Text(_state == MeasurementState.finished ? 'MAX Nm' : 'Nm',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
          ]),

          // Przycisk ręcznego wybiegu
          if (_state == MeasurementState.accelerating)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: _manualCoast,
                icon: const Icon(Icons.arrow_downward,
                    color: Colors.orangeAccent, size: 16),
                label: const Text('ZDJĄŁEM GAZ → START WYBIEGU',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orangeAccent),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6)),
              ),
            ),

          const SizedBox(height: 6),

          // Wykres
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(right: 18, top: 12),
              decoration: BoxDecoration(
                  color: Colors.grey[950],
                  borderRadius: BorderRadius.circular(14)),
              child: LineChart(LineChartData(
                minX: minX, maxX: maxX, minY: 0,
                maxY: _maxHp > 100 ? _maxHp + 30 : 200,
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: Colors.greenAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                        show: true,
                        color: Colors.greenAccent.withValues(alpha: 0.06)),
                  ),
                ],
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('KM',
                        style: TextStyle(color: Colors.grey, fontSize: 10)),
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 9)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(
                        _useRpm ? 'RPM' : 'km/h',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 10)),
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 24,
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 9)),
                    ),
                  ),
                ),
                gridData: const FlGridData(
                    show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
              )),
            ),
          ),

          const SizedBox(height: 10),

          // Przyciski po zakończeniu
          if (_state == MeasurementState.finished) ...[
            if (_savedRun != null)
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bar_chart, color: Colors.white),
                  label: const Text('ZOBACZ WYKRES',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => RunDetailScreen(
                      run: _savedRun!,
                      car: widget.car,
                      onExportPdf: () {},
                      onExportPrintPdf: () {},
                      onExportXml: () {
                        ExportService().exportXml(
                            runs: [_savedRun!], car: widget.car);
                      },
                    )),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            if (_allSamples.isNotEmpty)
              SizedBox(
                width: double.infinity, height: 42,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orangeAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.analytics_outlined,
                      color: Colors.orangeAccent, size: 18),
                  label: Text(
                    'REPLAY GPS  (${_allSamples.length} próbek)',
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 13),
                  ),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GpsReplayScreen(
                        samples: List.from(_allSamples)))),
                ),
              ),
            const SizedBox(height: 6),
          ],

          // Przycisk Start
          GestureDetector(
            onTap: (_state == MeasurementState.accelerating ||
                    _state == MeasurementState.coasting)
                ? null
                : _startMeasurement,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_state == MeasurementState.idle ||
                        _state == MeasurementState.finished)
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                border: Border.all(
                  color: (_state == MeasurementState.idle ||
                          _state == MeasurementState.finished)
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  width: 3,
                ),
              ),
              child: Icon(
                (_state == MeasurementState.idle ||
                        _state == MeasurementState.finished)
                    ? Icons.play_arrow
                    : Icons.fiber_manual_record,
                color: (_state == MeasurementState.idle ||
                        _state == MeasurementState.finished)
                    ? Colors.greenAccent
                    : Colors.redAccent,
                size: 40,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}