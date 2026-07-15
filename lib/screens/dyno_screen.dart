import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/car_profile.dart';
import '../utils/physics_engine.dart';
import '../services/bluetooth_service.dart';
import '../services/measurement_upload_service.dart';
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

  StreamSubscription<GpsFrame>? _frameSub;

  static const double _rotationalFactor = 1.05;

  double _currentSpeed = 0.0;
  double _currentHp    = 0.0;
  double _currentNm    = 0.0;
  double _maxHp        = 0.0;
  double _maxNm        = 0.0;

  double _lastSpeed      = 0.0;
  double _lastSmoothedHp = 0.0;

  // Sprzętowe czasy z ESP32
  int?   _lastGpsTimeMs;
  int?   _accStartTimeMs;
  double _syntheticTimeFallback = 0.0;

  int _warmupFrames = 0;

  // Wybieg: surowe [czas_s, prędkość_kmh] — cały segment, do fitu globalnego
  final List<List<double>> _coastRaw = [];
  double _coastCumTime = 0.0;

  int    _countdown      = 0;
  Timer? _countdownTimer;
  double    _coastingElapsed = 0.0;
  DateTime? _coastingStart;
  Timer?    _coastingTimer;

  final List<FlSpot>       _spots      = [];
  final List<GpsSample>    _allSamples = [];
  final List<List<double>> _accRaw     = [];

  DynoRun? _savedRun;

  // ── Status licencji BLE ──────────────────────────────────────
  BleAuthState _bleAuthState = BleAuthState.unknown;
  StreamSubscription<BleAuthState>? _authSub;

  // ── Zakres wykresu z ustawień ─────────────────────────────────
  double _chartMinX = 1000.0;  // domyślnie 1000 RPM
  double _chartMaxX = 6000.0;  // domyślnie 6000 RPM

  double get _weight => widget.overrideWeight ?? widget.car.weightKg;
  // kFactor zawsze wymagany — kalibracja obowiązkowa przed pomiarem

  @override
  void initState() {
    super.initState();
    _bleAuthState = btService.authState;
    _authSub = btService.licenseStatusStream.listen((state) {
      if (mounted) setState(() => _bleAuthState = state);
    });
    // Wczytaj zakres wykresu z ustawień
    dbService.getWorkshopSettings().then((ws) {
      if (mounted) setState(() {
        _chartMinX = ws.chartMinX;
        _chartMaxX = ws.chartMaxX;
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _frameSub?.cancel();
    _coastingTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _currentSpeed = _currentHp = _currentNm = _maxHp = _maxNm = 0;
    _lastSpeed = 0.0;
    _lastSmoothedHp = 0.0;
    _lastGpsTimeMs = null;
    _accStartTimeMs = null;
    _syntheticTimeFallback = 0.0;
    _warmupFrames = 0;
    _coastRaw.clear();
    _coastCumTime = 0.0;
    _countdown = 0;
    _countdownTimer?.cancel();
    _coastingElapsed = 0;
    _coastingStart = null;
    _coastingTimer?.cancel();
    _spots.clear();
    _allSamples.clear();
    _accRaw.clear();
    _savedRun = null;
  }

  void _startMeasurement() {
    if (!btService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ESP32 not connected')));
      return;
    }

    // Blokuj start gdy licencja niezweryfikowana
    // (notSupported = stary firmware — przepuszczamy dla kompatybilności)
    final auth = btService.authState;
    if (auth == BleAuthState.unauthorized ||
        auth == BleAuthState.noLicense) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth == BleAuthState.noLicense
          ? 'No licence. Please log in.'
          : 'Nieautoryzowane urządzenie. Sprawdź czy to Twój sprzęt.'),
        backgroundColor: const Color(0xFFE51C1C),
      ));
      return;
    }

    if (auth == BleAuthState.verifying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifying licence, please wait…')));
      return;
    }
    setState(() {
      _reset();
      _countdown = 3;
      _state = MeasurementState.idle;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        setState(() => _state = MeasurementState.accelerating);
        _frameSub = btService.frameStream.listen(_onFrame);
      }
    });
  }

  void _onFrame(GpsFrame frame) {
    if (_state == MeasurementState.idle ||
        _state == MeasurementState.finished) {
      return;
    }

    final rawSpeed = frame.speed;
    final currentGpsTime = frame.gpsTimeMs;

    // ── dt z zegara ESP32 ──
    double dt = 0.100;
    if (_lastGpsTimeMs != null && currentGpsTime != null) {
      dt = (currentGpsTime - _lastGpsTimeMs!) / 1000.0;
      if (dt <= 0 || dt > 1.0) dt = 0.100;
    }
    _lastGpsTimeMs = currentGpsTime;

    if (dt < 0.05 && currentGpsTime == null) return;

    // ── Walidacja ──
    final isDropout = _lastSpeed > 10.0 && rawSpeed < 1.0;
    final isJump = (_lastSpeed > 0) &&
        (rawSpeed - _lastSpeed).abs() > (42.0 * dt + 2.0) &&
        rawSpeed > 0.5;

    if (isDropout || isJump) {
      _allSamples.add(GpsSample(
        speed: rawSpeed, dt: dt, rejected: true,
        reason: isDropout ? 'Dropout' : 'Skok',
        phase: _state == MeasurementState.accelerating ? 'ACC' : 'COAST',
      ));
      return;
    }

    // ── Warmup ──
    if (_warmupFrames < 10) {
      _warmupFrames++;
      _allSamples.add(GpsSample(
        speed: rawSpeed, dt: dt, rejected: true,
        reason: 'Warmup', phase: 'ACC',
      ));
      _lastSpeed = rawSpeed;
      setState(() => _currentSpeed = rawSpeed);
      return;
    }

    _allSamples.add(GpsSample(
      speed: rawSpeed, dt: dt, rejected: false, reason: '',
      phase: _state == MeasurementState.accelerating ? 'ACC' : 'COAST',
    ));

    // ── PRZYSPIESZANIE ──
    if (_state == MeasurementState.accelerating) {
      if (_accStartTimeMs == null && currentGpsTime != null) {
        _accStartTimeMs = currentGpsTime;
      }

      double relTime;
      if (_accStartTimeMs != null && currentGpsTime != null) {
        relTime = (currentGpsTime - _accStartTimeMs!) / 1000.0;
      } else {
        _syntheticTimeFallback += dt;
        relTime = _syntheticTimeFallback;
      }

      _accRaw.add([relTime, rawSpeed]);

      if (_lastSpeed > 15.0 && rawSpeed > _lastSpeed + 0.05) {
        final hpRaw = PhysicsEngine.calculateWheelHp(
          v1KmH: _lastSpeed, v2KmH: rawSpeed,
          timeDelta: dt, weight: _weight,
          rotationalFactor: _rotationalFactor,
        );

        if (_lastSmoothedHp == 0) _lastSmoothedHp = hpRaw;
        // EMA 0.08/0.92 zamiast 0.15/0.85 — wyłącznie do podglądu na żywo,
        // nie wpływa na obliczenia regresji końcowej (ta korzysta z _accRaw).
        final hpLiveEma = hpRaw * 0.08 + _lastSmoothedHp * 0.92;
        _lastSmoothedHp = hpLiveEma;

        if (hpLiveEma > 0 && hpLiveEma < 1000) {
          final kf   = widget.kFactor ?? 1.0;
          final xVal = rawSpeed * kf;  // zawsze RPM
          final lastX = _spots.isNotEmpty ? _spots.last.x : 0.0;
          const step  = 30.0;  // krok w RPM

          double nmLive = 0;
          if (xVal > 0) {
            nmLive = (hpLiveEma * 7023.5) / xVal;
          }

          setState(() {
            _currentHp = hpLiveEma;
            _currentNm = nmLive;
            if (hpLiveEma > _maxHp) _maxHp = hpLiveEma;
            if (nmLive > _maxNm) _maxNm = nmLive;
            if (xVal >= lastX + step) {
              _spots.add(FlSpot(xVal, hpLiveEma));
            }
          });
        }
      }
    }

    // ── WYBIEG: zbieramy SUROWE [czas, prędkość] do globalnego fitu ──
    else if (_state == MeasurementState.coasting) {
      _coastCumTime += dt;
      _coastRaw.add([_coastCumTime, rawSpeed]);

      // Prosty wskaźnik na żywo (średnia strata w oknie)
      if (_coastRaw.length > 5) {
        final recent5 = _coastRaw.sublist(_coastRaw.length - 5);
        final vFirst = recent5.first[1];
        final vLast  = recent5.last[1];
        final dtWin  = recent5.last[0] - recent5.first[0];
        if (vFirst > vLast && dtWin > 0) {
          final liveHp = PhysicsEngine.calculateCoastLossHp(
            v1KmH: vFirst, v2KmH: vLast,
            timeDelta: dtWin, weight: _weight,
            rotationalFactor: _rotationalFactor,
          );
          setState(() => _currentHp = liveHp);
        }
      }
    }

    setState(() {
      _currentSpeed = rawSpeed;
      _lastSpeed = rawSpeed;
    });
  }

  void _manualCoast() {
    if (_state != MeasurementState.accelerating) return;
    _startCoasting();
  }

  void _startCoasting() {
    _coastingStart = DateTime.now();
    _coastingTimer?.cancel();
    _coastingTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted || _state != MeasurementState.coasting) {
        t.cancel(); return;
      }
      final elapsed = DateTime.now()
          .difference(_coastingStart!).inMilliseconds / 1000.0;
      setState(() => _coastingElapsed = elapsed);
      if (elapsed >= 15.0) { t.cancel(); _stopAndSave(); }
    });
    setState(() {
      _state           = MeasurementState.coasting;
      _coastingElapsed = 0.0;
    });
  }

  Future<void> _stopAndSave() async {
    _frameSub?.cancel();
    setState(() => _state = MeasurementState.finished);

    // ── Model fizyczny strat z CAŁEGO wybiegu ──
    final coastModel = PhysicsEngine.fitCoastPhysicsModel(_coastRaw);
    debugPrint('[DYNO] Coast model: CrrG=${coastModel[0].toStringAsFixed(5)}'
        ' Kaero=${coastModel[1].toStringAsFixed(7)}'
        ' (${_coastRaw.length} próbek)');

    // ── Regresja wielomianowa mocy ──
    List<FlSpot> sourceSpots;
    if (_accRaw.length >= 20) {
      final polyPts = PhysicsEngine.polynomialPowerCurve(
        timeSpeedPoints: _accRaw,
        weight: _weight,
        rotationalFactor: _rotationalFactor,
        degree: 4,
      );
      if (polyPts.length >= 5) {
        sourceSpots = polyPts.map((p) => FlSpot(p[0], p[1])).toList();
      } else {
        sourceSpots = _spots;
      }
    } else {
      sourceSpots = _spots;
    }

    // ── Korekta strat + wynik końcowy ──
    final correctedSpots = <FlSpot>[];
    final dataPoints     = <String>[];
    double maxHp = 0, maxNm = 0;

    for (final spot in sourceSpots) {
      final speedKmh = spot.x;
      final hpWheel  = spot.y;

      // Model fizyczny: loss(v) bez clampu — działa przy KAŻDEJ prędkości
      final loss = _coastRaw.isEmpty ? 0.0
          : PhysicsEngine.coastLossAtSpeed(
              speedKmh, coastModel, _weight,
              rotationalFactor: _rotationalFactor);

      final finalHp = (hpWheel + loss) * widget.weatherCf;

      final kf     = widget.kFactor ?? 1.0;
      final rpm    = speedKmh * kf;
      final finalNm = rpm > 0 ? (finalHp * 7023.5) / rpm : 0.0;

      correctedSpots.add(FlSpot(rpm, finalHp));  // oś X = RPM zawsze
      dataPoints.add(
        '${rpm.toStringAsFixed(0)};'
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
      graphDataPoints:  dataPoints,
    );
    await dbService.saveRun(run);
    if (!mounted) return;

    // ── Upload do chmury (jeśli user ma cloud sync włączony) ──
    // Robimy w tle, nie blokuje UI, błąd jest tylko logowany
    final uploadSvc = MeasurementUploadService(authService);
    uploadSvc.upload(
      maxHp:        maxHp,
      maxNm:        maxNm,
      weightKg:     _weight,
      correction:   widget.weatherCf,
      measuredAt:   run.timestamp,
      vehicleName:  widget.car.name,
      licencePlate: widget.car.licensePlate,
      run:          run,
    ).then((ok) async {
      if (ok) {
        // Oznacz lokalny pomiar jako zsynchronizowany
        await dbService.markRunSynced(run.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('☁️ Pomiar zsynchronizowany z chmurą'),
              backgroundColor: Colors.blueAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });

    setState(() {
      _spots..clear()..addAll(correctedSpots);
      _maxHp    = maxHp;
      _maxNm    = maxNm;
      _savedRun = run;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Zapisano! ${maxHp.toStringAsFixed(1)} KM'
          '${maxNm > 0 ? " / ${maxNm.toStringAsFixed(1)} Nm" : ""}'),
      backgroundColor: Colors.greenAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    String statusText = btService.isConnected
        ? 'READY TO START' : 'WAITING FOR ESP32...';
    Color statusColor = btService.isConnected
        ? Colors.grey : Colors.orangeAccent;

    // Nadpisz status jeśli trwa weryfikacja licencji lub odmowa
    if (btService.isConnected) {
      switch (_bleAuthState) {
        case BleAuthState.verifying:
          statusText  = '🔐 VERIFICATION IN PROGRESS...';
          statusColor = Colors.orangeAccent;
          break;
        case BleAuthState.unauthorized:
          statusText  = '⛔ UNAUTHORIZED DEVICE';
          statusColor = const Color(0xFFE51C1C);
          break;
        case BleAuthState.noLicense:
          statusText  = '⚠️ NO LICENSE — PLEASE LOG IN';
          statusColor = const Color(0xFFE51C1C);
          break;
        case BleAuthState.authorized:
          statusText  = 'READY TO START ✓';
          statusColor = Colors.grey;
          break;
        case BleAuthState.notSupported:
          statusText  = 'CONNECTED (legacy mode)';
          statusColor = Colors.grey;
          break;
        case BleAuthState.unknown:
          statusText  = 'CONNECTING...';
          statusColor = Colors.orangeAccent;
          break;
      }
    }

    if (_countdown > 0) {
      statusText  = 'START IN $_countdown...';
      statusColor = Colors.yellowAccent;
    } else if (_state == MeasurementState.accelerating) {
      statusText  = 'ACCELERATING';
      statusColor = Colors.greenAccent;
    } else if (_state == MeasurementState.coasting) {
      statusText  = 'COASTING: DO NOT BRAKE!';
      statusColor = Colors.orangeAccent;
    } else if (_state == MeasurementState.finished) {
      statusText  = 'SAVE COMPLETE';
      statusColor = const Color(0xFFE51C1C);
    }

    // Zakres osi X — RPM z ustawień lub dynamicznie z danych
    final double minX = _spots.isEmpty
        ? _chartMinX
        : (_spots.first.x - 100.0).clamp(_chartMinX, double.infinity);
    final double maxX = _spots.isEmpty
        ? _chartMaxX
        : (_spots.last.x + 200.0).clamp(0.0, _chartMaxX);

    // Dynamiczne maxY — zaokrąglone do 50, min 2× peak
    final double peakY = _spots.isEmpty ? 100.0
        : _spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final double maxY = ((peakY * 2.0) / 50).ceil() * 50.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dyno Run',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(children: [
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
                    backgroundColor: const Color(0xFF1a1a1a),
                    color: Colors.orangeAccent, minHeight: 6,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(_currentSpeed.toStringAsFixed(1),
              style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold)),
          const Text('km/h',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [
              Text(
                _state == MeasurementState.finished
                    ? _maxHp.toStringAsFixed(1)
                    : _currentHp.toStringAsFixed(1),
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
              Text(_state == MeasurementState.finished ? 'MAX HP' : 'KM',
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
          if (_state == MeasurementState.accelerating)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: _manualCoast,
                icon: const Icon(Icons.arrow_downward,
                    color: Colors.orangeAccent, size: 16),
                label: const Text('THROTTLE OFF → COAST DOWN',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orangeAccent),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6)),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(right: 18, top: 12),
              decoration: BoxDecoration(
                  color: Colors.grey[950],
                  borderRadius: BorderRadius.circular(14)),
              child: LineChart(LineChartData(
                minX: minX, maxX: maxX, minY: 0,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots, isCurved: true,
                    curveSmoothness: 0.35, color: Colors.greenAccent,
                    barWidth: 3, isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true,
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
                    sideTitles: SideTitles(showTitles: true, reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 9)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('RPM',
                        style: TextStyle(
                            color: Colors.grey, fontSize: 10)),
                    sideTitles: SideTitles(showTitles: true, reservedSize: 24,
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
                  label: const Text('VIEW CHART',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => RunDetailScreen(
                      run: _savedRun!, car: widget.car,
                      onExportPdf: () async {
                        // PDF mobilny — eksport bez kalibracji (brak RPM)
                        final svc = ExportService();
                        await svc.exportMobilePdf(
                          run: _savedRun!,
                          car: widget.car,
                        );
                      },
                      onExportPrintPdf: () async {
                        if (widget.kFactor == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text(
                              'No calibration — A4 export unavailable')));
                          return;
                        }
                        final svc     = ExportService();
                        final ws      = await dbService.getWorkshopSettings();
                        await svc.exportPrintPdf(
                          run: _savedRun!, car: widget.car,
                          workshop: ws, kFactor: widget.kFactor!);
                      },
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
                        color: Colors.orangeAccent, fontSize: 13)),
                  onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GpsReplayScreen(
                        samples: List.from(_allSamples)))),
                ),
              ),
            const SizedBox(height: 6),
          ],
          GestureDetector(
            onTap: (_state == MeasurementState.accelerating ||
                    _state == MeasurementState.coasting)
                ? null : _startMeasurement,
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
                      ? Colors.greenAccent : const Color(0xFFE51C1C),
                  width: 3,
                ),
              ),
              child: Icon(
                (_state == MeasurementState.idle ||
                        _state == MeasurementState.finished)
                    ? Icons.play_arrow : Icons.fiber_manual_record,
                color: (_state == MeasurementState.idle ||
                        _state == MeasurementState.finished)
                    ? Colors.greenAccent : const Color(0xFFE51C1C),
                size: 40,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}