import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';

class CalibrationScreen extends StatefulWidget {
  final int? carId; // Opcjonalnie przekazujemy carId
  const CalibrationScreen({super.key, this.carId});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  StreamSubscription<double>? _speedSubscription;
  double _currentSpeed    = 0.0;
  double _displaySpeed    = 0.0;   // wygładzona prędkość do wyświetlania
  int    _zeroCount       = 0;     // ile kolejnych zer zliczono
  static const _emaAlpha  = 0.15;  // współczynnik wygładzania (0=brak, 1=brak wygładzania)
  static const _zeroDelay = 8;     // ile zer z rzędu zanim uznamy że naprawdę 0
  Map<String, double>? _savedCalibration;
  int? _activeCarId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCalibration();
    _speedSubscription = btService.speedStream.listen((speed) {
      setState(() {
        if (speed <= 0) {
          // Nie zeruj od razu — poczekaj na kilka kolejnych zer
          _zeroCount++;
          if (_zeroCount >= _zeroDelay) {
            _currentSpeed = 0;
            _displaySpeed = 0;
          }
          // Jeśli mniej zer — zachowaj ostatnią prędkość
        } else {
          _zeroCount = 0;
          // EMA wygładzanie
          if (_currentSpeed <= 0) {
            _currentSpeed = speed;
            _displaySpeed = speed;
          } else {
            _currentSpeed = _emaAlpha * speed + (1 - _emaAlpha) * _currentSpeed;
            _displaySpeed = _currentSpeed;
          }
        }
      });
    });
  }

  Future<void> _loadCalibration() async {
    // Pobierz aktywne auto
    final cars = await dbService.getAllCars();
    if (cars.isEmpty) return;
    final carId = widget.carId ?? cars.first.id;
    setState(() => _activeCarId = carId);

    final cal = await dbService.getLatestCalibration(carId);
    setState(() => _savedCalibration = cal);
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _saveCalibration() async {
    if (_activeCarId == null || _currentSpeed < 5) return;
    setState(() => _saving = true);

    await dbService.saveCalibration(_activeCarId!, _currentSpeed);
    final cal = await dbService.getLatestCalibration(_activeCarId!);

    setState(() {
      _savedCalibration = cal;
      _saving = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Zapisano! ${_currentSpeed.toStringAsFixed(0)} km/h @ 3000 RPM  '
          '→ k=${cal!['kFactor']!.toStringAsFixed(2)} RPM/(km/h)',
        ),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = btService.isConnected;
    final bool canSave = connected && _currentSpeed > 5 && !_saving;

    // Oblicz podgląd RPM przy obecnej prędkości (jeśli mamy kalibrację)
    double? previewRpm;
    if (_savedCalibration != null && _currentSpeed > 0) {
      previewRpm = _currentSpeed * _savedCalibration!['kFactor']!;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('K-Factor Calibration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Instrukcja
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('How to calibrate:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('1. Drive on a road and select a direct gear (3rd or 4th)'),
                    Text('2. Hold exactly 3 000 RPM steady'),
                    Text('3. When speed stabilises — tap SAVE'),
                    SizedBox(height: 8),
                    Text('This coefficient is used to calculate RPM and torque during a run.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Status GPS
              Text(
                connected ? 'GPS active' : 'ESP32 not connected',
                style: TextStyle(
                  color: connected ? Colors.greenAccent : const Color(0xFFE51C1C),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 20),

              // Prędkość na żywo
              Text(
                _displaySpeed.toStringAsFixed(0),
                style: const TextStyle(fontSize: 90, fontWeight: FontWeight.bold),
              ),
              const Text('km/h @ 3000 RPM',
                  style: TextStyle(fontSize: 18, color: Colors.blueAccent)),

              // Podgląd RPM przy obecnej prędkości
              if (previewRpm != null) ...[
                const SizedBox(height: 8),
                Text(
                  '≈ ${previewRpm.toStringAsFixed(0)} RPM now',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],

              const SizedBox(height: 30),

              // Ostatnia kalibracja
              if (_savedCalibration != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current calibration:',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${_savedCalibration!['speedAt3000rpm']!.toStringAsFixed(1)} km/h → '
                        'k = ${_savedCalibration!['kFactor']!.toStringAsFixed(2)} RPM/(km/h)',
                        style: const TextStyle(
                            color: Colors.greenAccent, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Example: 100 km/h = ${(100 * _savedCalibration!['kFactor']!).toStringAsFixed(0)} RPM',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 30),

              // Przycisk zapisu
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSave ? Colors.blueAccent : Colors.grey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: canSave ? _saveCalibration : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    _currentSpeed < 5
                        ? 'Drive at 3000 RPM to enable saving'
                        : 'SAVE CALIBRATION',
                    style: const TextStyle(
                        fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              if (!connected)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Connect to ESP32 from the main screen',
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}