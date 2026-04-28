import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  StreamSubscription<double>? _speedSubscription;
  double _currentSpeed = 0.0;
  double? _savedSpeed;

  @override
  void initState() {
    super.initState();
    _speedSubscription = btService.speedStream.listen((speed) {
      setState(() => _currentSpeed = speed);
    });
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    super.dispose();
  }

  void _saveCalibration() {
    setState(() => _savedSpeed = _currentSpeed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Kalibracja zapisana: ${_currentSpeed.toStringAsFixed(1)} km/h @ 3000 RPM / 3. bieg',
        ),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = btService.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalibracja'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Utrzymaj stałe 3000 RPM na 3. biegu',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              connected ? 'GPS aktywny' : 'Brak połączenia z ESP32',
              style: TextStyle(
                color: connected ? Colors.greenAccent : Colors.redAccent,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),

            // Prędkość na żywo z GPS
            Text(
              _currentSpeed.toStringAsFixed(1),
              style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold),
            ),
            const Text(
              'km/h (Sygnał GPS)',
              style: TextStyle(fontSize: 20, color: Colors.blueAccent),
            ),

            // Ostatnia zapisana kalibracja
            if (_savedSpeed != null) ...[
              const SizedBox(height: 20),
              Text(
                'Ostatnia kalibracja: ${_savedSpeed!.toStringAsFixed(1)} km/h',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],

            const SizedBox(height: 60),

            SizedBox(
              height: 70,
              width: 300,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: connected ? Colors.blueAccent : Colors.grey,
                ),
                onPressed: connected ? _saveCalibration : null,
                child: const Text(
                  'ZAPISZ KALIBRACJĘ',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (!connected)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Połącz się z ESP32 na ekranie głównym',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}