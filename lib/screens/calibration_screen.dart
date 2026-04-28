import 'package:flutter/material.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalibracja Obrotów'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Utrzymaj stałe 3000 RPM na 3. biegu', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 40),
            const Text('85.4', style: TextStyle(fontSize: 80, fontWeight: FontWeight.bold)),
            const Text('km/h (Sygnał GPS)', style: TextStyle(fontSize: 20, color: Colors.blueAccent)),
            const SizedBox(height: 60),
            SizedBox(
              height: 70, width: 300,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () {
                  debugPrint("Skalibrowano!");
                },
                child: const Text('ZAPISZ KALIBRACJĘ', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}