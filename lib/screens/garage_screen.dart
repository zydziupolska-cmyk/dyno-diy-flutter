import 'package:flutter/material.dart';
import '../models/car_profile.dart';
import '../main.dart';

class GarageScreen extends StatefulWidget {
  final CarProfile car;
  const GarageScreen({super.key, required this.car});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  late TextEditingController _weightController;
  late TextEditingController _tempController;
  late TextEditingController _pressureController;

  @override
  void initState() {
    super.initState();

    // Czytaj z sessionCache – dane przeżywają przełączanie zakładek
    final cached = sessionCache[widget.car.id];
    _weightController   = TextEditingController(
        text: (cached?['weight'] ?? widget.car.weightKg).toStringAsFixed(0));
    _tempController     = TextEditingController(
        text: (cached?['temp'] ?? 20.0).toStringAsFixed(0));
    _pressureController = TextEditingController(
        text: (cached?['pressure'] ?? 1013.0).toStringAsFixed(0));

    // Zapisuj zmiany na bieżąco do cache
    _weightController.addListener(_saveToCache);
    _tempController.addListener(_saveToCache);
    _pressureController.addListener(_saveToCache);
  }

  void _saveToCache() {
    final weight   = double.tryParse(_weightController.text)   ?? widget.car.weightKg;
    final temp     = double.tryParse(_tempController.text)     ?? 20.0;
    final pressure = double.tryParse(_pressureController.text) ?? 1013.0;

    sessionCache[widget.car.id] = {
      'weight':   weight,
      'temp':     temp,
      'pressure': pressure,
    };
  }

  void _saveWeightToDb(String val) {
    final newWeight = double.tryParse(val);
    if (newWeight == null) return;
    final updated = CarProfile(
      id: widget.car.id,
      name: widget.car.name,
      licensePlate: widget.car.licensePlate,
      weightKg: newWeight,
      area: widget.car.area,
      cd: widget.car.cd,
      lossDrivetrain: widget.car.lossDrivetrain,
      transmission: widget.car.transmission,
    );
    dbService.saveCar(updated);
  }

  @override
  void dispose() {
    _weightController.removeListener(_saveToCache);
    _tempController.removeListener(_saveToCache);
    _pressureController.removeListener(_saveToCache);
    _weightController.dispose();
    _tempController.dispose();
    _pressureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ustawienia: ${widget.car.name}'),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Parametry pojazdu:',
                style: TextStyle(fontSize: 18, color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Waga (kg) = Auto + Kierowca + Paliwo',
                border: OutlineInputBorder(),
                suffixText: 'kg',
                prefixIcon: Icon(Icons.monitor_weight),
              ),
              onChanged: _saveWeightToDb,
            ),
            const SizedBox(height: 30),
            const Text('Warunki do korekcji (Norma DIN):',
                style: TextStyle(fontSize: 18, color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tempController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Temperatura',
                      border: OutlineInputBorder(),
                      suffixText: '°C',
                      prefixIcon: Icon(Icons.thermostat),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _pressureController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ciśnienie',
                      border: OutlineInputBorder(),
                      suffixText: 'hPa',
                      prefixIcon: Icon(Icons.speed),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Card(
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent, size: 30),
                    SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        'Dokładna waga to klucz do poprawnego pomiaru '
                        '(błąd 50kg to ok. 3-5% przekłamania wyniku). '
                        'Temperatura i ciśnienie posłużą do korekcji '
                        'wyników wg normy DIN 70020.',
                        style: TextStyle(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}