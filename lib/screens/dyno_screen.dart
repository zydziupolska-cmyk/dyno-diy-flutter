import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../main.dart';
import 'history_screen.dart';
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

  double _currentSpeed     = 0.0;
  double _currentHp        = 0.0;
  double _currentNm        = 0.0;
  double _maxHp            = 0.0;
  double _maxNm            = 0.0;
  double _lastSpeed        = 0.0;
  double _lastSmoothedHp   = 0.0;
  double _lastSmoothedLoss = 0.0;
  DateTime? _lastTime;

  // Wybieg — liczymy na podstawie czasu rzeczywistego
  Timer? _coastTimer;
  double _coastingElapsed  = 0.0;
  final double _maxCoast   = 20.0;

  // Detekcja końca przyspieszania
  int _noAccelCount = 0;

  List<FlSpot> _hpSpots  = [];
  final List<List<double>> _lossPoints = [];
  DynoRun? _lastSavedRun;

  StreamSubscription<double>? _speedSub;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    _coastTimer?.cancel();
    super.dispose();
  }

  double get _weight => widget.overrideWeight ?? widget.car.weightKg;

  // ── START ─────────────────────────────────────────────────────────────────
  void _start() {
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESP32 nie jest połączony')));
      return;
    }

    setState(() {
      _state           = MeasurementState.accelerating;
      _currentSpeed    = 0;
      _currentHp       = 0;
      _currentNm       = 0;
      _maxHp           = 0;
      _maxNm           = 0;
      _lastSpeed       = 0;
      _lastSmoothedHp  = 0;
      _lastSmoothedLoss= 0;
      _noAccelCount    = 0;
      _coastingElapsed = 0;
      _hpSpots.clear();
      _lossPoints.clear();
      _lastSavedRun    = null;
      _lastTime        = DateTime.now();
    });

    _speedSub = btService.speedStream.listen(_onSpeed);
  }

  // ── KAŻDA PRÓBKA GPS ──────────────────────────────────────────────────────
  void _onSpeed(double gpsSpeed) {
    if (_state == MeasurementState.idle ||
        _state == MeasurementState.finished) { return; }

    final now = DateTime.now();
    final dt  = _lastTime != null
        ? now.difference(_lastTime!).inMilliseconds / 1000.0
        : 0.1;

    // Ignoruj duplikaty (< 80ms)
    if (dt < 0.08) return;

    final speed = gpsSpeed;

    if (_state == MeasurementState.accelerating) {
      _processAcceleration(speed, dt);
    } else if (_state == MeasurementState.coasting) {
      _processCoasting(speed, dt);
    }

    setState(() {
      _currentSpeed = speed;
      _lastSpeed    = speed;
      _lastTime     = now;
    });
  }

  // ── PRZYSPIESZANIE ────────────────────────────────────────────────────────
  void _processAcceleration(double speed, double dt) {
    // Czy prędkość rośnie?
    final growing = speed > _lastSpeed + 0.2;

    if (growing) {
      _noAccelCount = 0;

      // Moc na kołach = m × a × v
      final hpRaw = PhysicsEngine.calculateWheelHp(
        v1KmH: _lastSpeed,
        v2KmH: speed,
        timeDelta: dt,
        weight: _weight,
      );

      // EMA alpha=0.5
      final hp = PhysicsEngine.ema(hpRaw, _lastSmoothedHp, 0.50);
      _lastSmoothedHp = hp;

      // Nm live
      double nm = 0;
      if (widget.kFactor != null && widget.kFactor! > 0 && speed > 0) {
        final rpm = speed * widget.kFactor!;
        if (rpm > 0) nm = (hp * 9550.0) / rpm;
      }

      // Punkt wykresu (X = RPM lub km/h)
      final xVal = (widget.kFactor != null && widget.kFactor! > 0)
          ? speed * widget.kFactor!
          : speed;
      final lastX = _hpSpots.isNotEmpty ? _hpSpots.last.x : 0.0;
      final step  = widget.kFactor != null ? 50.0 : 1.0;

      setState(() {
        _currentHp = hp;
        _currentNm = nm;
        if (hp > _maxHp) _maxHp = hp;
        if (nm > _maxNm) _maxNm = nm;
        if (speed > 20 && hp > 5 && xVal >= lastX + step) {
          _hpSpots.add(FlSpot(xVal, hp));
        }
      });
    } else {
      _noAccelCount++;
    }

    // Koniec przyspieszania gdy:
    // - prędkość wyraźnie spada (zjazd z gazu / sprzęgło)
    // - LUB brak wzrostu przez 2.5s (25 próbek × 100ms)
    final drop    = speed < _lastSpeed - 2.0;
    final timeout = _noAccelCount >= 25 && speed > 30;

    if (drop || timeout) {
      _startCoasting();
    }
  }

  // ── START WYBIEGU ─────────────────────────────────────────────────────────
  void _startCoasting() {
    setState(() {
      _state           = MeasurementState.coasting;
      _coastingElapsed = 0.0;
      _lastSmoothedLoss= 0.0;
      _noAccelCount    = 0;
    });

    // Timer co 100ms — niezależny od GPS
    _coastTimer?.cancel();
    _coastTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (_state != MeasurementState.coasting) {
        t.cancel();
        return;
      }
      setState(() => _coastingElapsed += 0.1);
      if (_coastingElapsed >= _maxCoast) {
        t.cancel();
        _stopAndSave();
      }
    });
  }

  // ── WYBIEG ────────────────────────────────────────────────────────────────
  void _processCoasting(double speed, double dt) {
    // Koniec wybiegu gdy prędkość < 20 km/h
    if (speed <= 20) {
      _coastTimer?.cancel();
      _stopAndSave();
      return;
    }

    if (_lastSpeed <= 0 || speed >= _lastSpeed) return;

    // Straty = m × decel × v
    final lossRaw = PhysicsEngine.calculateCoastLossHp(
      v1KmH: _lastSpeed,
      v2KmH: speed,
      timeDelta: dt,
      weight: _weight,
    );

    final loss = PhysicsEngine.ema(lossRaw, _lastSmoothedLoss, 0.55);

    if (loss > 0 && loss < 150) {
      setState(() {
        _currentHp        = loss;
        _lastSmoothedLoss = loss;
        _lossPoints.add([speed, loss]);
      });
    }
  }

  // ── PRZYCISK RĘCZNY ───────────────────────────────────────────────────────
  void _manualCoast() {
    if (_state != MeasurementState.accelerating) return;
    _startCoasting();
  }

  // ── ZAPIS WYNIKÓW ─────────────────────────────────────────────────────────
  Future<void> _stopAndSave() async {
    _speedSub?.cancel();
    _coastTimer?.cancel();
    if (_state == MeasurementState.finished) return;
    setState(() => _state = MeasurementState.finished);

    final reg = PhysicsEngine.calculateLossRegression(_lossPoints);
    final a   = reg['a'] ?? 0.0;
    final b   = reg['b'] ?? 0.0;

    debugPrint('[DYNO] Strat punktów: ${_lossPoints.length}, a=$a b=$b');

    List<FlSpot> corrected = [];
    List<String> data      = [];
    double maxHp = 0, maxNm = 0;

    for (final spot in _hpSpots) {
      // X jest w RPM lub km/h
      final xVal     = spot.x;
      final hpWheel  = spot.y;
      final speedKmh = (widget.kFactor != null && widget.kFactor! > 0)
          ? xVal / widget.kFactor!
          : xVal;

      final loss    = (a * speedKmh + b).clamp(0.0, 150.0);
      final finalHp = (hpWheel + loss) * widget.weatherCf;

      double finalNm = 0;
      if (widget.kFactor != null && widget.kFactor! > 0 && speedKmh > 0) {
        final rpm = speedKmh * widget.kFactor!;
        if (rpm > 0) finalNm = (finalHp * 9550.0) / rpm;
      }

      corrected.add(FlSpot(speedKmh, finalHp));
      data.add('${speedKmh.toStringAsFixed(1)};'
               '${finalHp.toStringAsFixed(1)};'
               '${finalNm.toStringAsFixed(1)}');

      if (finalHp > maxHp) maxHp = finalHp;
      if (finalNm > maxNm) maxNm = finalNm;
    }

    final run = DynoRun(
      carId:            widget.car.id,
      timestamp:        DateTime.now(),
      maxEngineHp:      maxHp,
      maxEngineTorque:  maxNm,
      sessionWeightKg:  _weight,
      correctionFactor: widget.weatherCf,
      graphDataPoints:  data,
    );

    await dbService.saveRun(run);
    if (!mounted) return;

    setState(() {
      // Pokaż wykres w km/h po zakończeniu
      _hpSpots       = corrected;
      _maxHp         = maxHp;
      _maxNm         = maxNm;
      _currentHp     = 0;
      _currentNm     = 0;
      _lastSavedRun  = run;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Zapisano! ${maxHp.toStringAsFixed(1)} KM'
            '${maxNm > 0 ? " / ${maxNm.toStringAsFixed(1)} Nm" : ""}')));
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    String statusText  = 'GOTOWY DO STARTU';
    Color  statusColor = Colors.grey;

    if (!btService.isConnected) {
      statusText  = 'CZEKAM NA ESP32...';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.accelerating) {
      statusText  = 'PRZYSPIESZANIE';
      statusColor = Colors.greenAccent;
    } else if (_state == MeasurementState.coasting) {
      statusText  = 'WYBIEG: NIE HAMOWAĆ!';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.finished) {
      statusText  = 'ZAPISANO';
      statusColor = Colors.redAccent;
    }

    // Zakres wykresu
    final bool useRpm = widget.kFactor != null && widget.kFactor! > 0;
    // Podczas pomiaru — RPM, po zakończeniu — km/h (dane zapisane w km/h)
    final double minX = _state == MeasurementState.finished
        ? 20.0
        : (useRpm ? 1000.0 : 20.0);
    final double maxX = _state == MeasurementState.finished
        ? 200.0
        : (useRpm ? 7000.0 : 200.0);
    final String xLabel = _state == MeasurementState.finished
        ? 'km/h'
        : (useRpm ? 'RPM' : 'km/h');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomiar Dyno',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // Status + pasek wybiegu
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor),
            ),
            child: Column(children: [
              Text(statusText, style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
              if (_state == MeasurementState.coasting)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(
                    value: _coastingElapsed / _maxCoast,
                    backgroundColor: Colors.grey[800],
                    color: Colors.orangeAccent,
                    minHeight: 7,
                  ),
                ),
            ]),
          ),

          const SizedBox(height: 14),

          // Prędkość
          Text(_currentSpeed.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 52, fontWeight: FontWeight.bold)),
          const Text('km/h',
              style: TextStyle(color: Colors.grey, fontSize: 13)),

          const SizedBox(height: 10),

          // KM i Nm
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _gauge(
                value: _state == MeasurementState.finished
                    ? _maxHp : _currentHp,
                label: _state == MeasurementState.finished
                    ? 'MAX KM' : 'KM',
                color: statusColor,
              ),
              if (widget.kFactor != null)
                _gauge(
                  value: _state == MeasurementState.finished
                      ? _maxNm : _currentNm,
                  label: _state == MeasurementState.finished
                      ? 'MAX Nm' : 'Nm',
                  color: Colors.blueAccent,
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Przycisk ręczny
          if (_state == MeasurementState.accelerating)
            OutlinedButton.icon(
              onPressed: _manualCoast,
              icon: const Icon(Icons.arrow_downward,
                  color: Colors.orangeAccent, size: 18),
              label: const Text('ZDJĄŁEM GAZ → START WYBIEGU',
                  style: TextStyle(
                      color: Colors.orangeAccent, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orangeAccent),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6)),
            ),

          const SizedBox(height: 6),

          // Wykres
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(right: 20, top: 14),
              decoration: BoxDecoration(
                  color: Colors.grey[950],
                  borderRadius: BorderRadius.circular(16)),
              child: LineChart(LineChartData(
                minX: minX, maxX: maxX,
                minY: 0,
                maxY: _maxHp > 80 ? _maxHp + 30 : 200,
                lineBarsData: [
                  LineChartBarData(
                    spots: _hpSpots,
                    isCurved: true,
                    curveSmoothness: 0.4,
                    color: Colors.greenAccent,
                    barWidth: 3,
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
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(xLabel,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 10)),
                    ),
                  ),
                ),
                gridData: const FlGridData(
                    show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
              )),
            ),
          ),

          const SizedBox(height: 12),

          // Przycisk "ZOBACZ WYKRES"
          if (_state == MeasurementState.finished &&
              _lastSavedRun != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bar_chart, color: Colors.white),
                  label: const Text('ZOBACZ WYKRES',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RunDetailScreen(
                        run: _lastSavedRun!,
                        car: widget.car,
                        onExportPdf: () {},
                        onExportPrintPdf: () {},
                        onExportXml: () => ExportService().exportXml(
                            runs: [_lastSavedRun!], car: widget.car),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Start/Stop
          GestureDetector(
            onTap: (_state == MeasurementState.accelerating ||
                    _state == MeasurementState.coasting)
                ? null
                : _start,
            child: Container(
              width: 86, height: 86,
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
                  width: 4,
                ),
              ),
              child: Center(
                child: Icon(
                  (_state == MeasurementState.idle ||
                          _state == MeasurementState.finished)
                      ? Icons.play_arrow
                      : Icons.save_outlined,
                  color: (_state == MeasurementState.idle ||
                          _state == MeasurementState.finished)
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 42,
                ),
              ),
            ),
          ),

        ]),
      ),
    );
  }

  Widget _gauge({
    required double value,
    required String label,
    required Color color,
  }) {
    return Column(children: [
      Text(value.toStringAsFixed(1),
          style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: color)),
      Text(label,
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }
}