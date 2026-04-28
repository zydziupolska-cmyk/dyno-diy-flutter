import 'package:flutter/material.dart';
import '../models/car_profile.dart';
import '../main.dart'; // Aby mieć dostęp do dbService

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
    // Ustawiamy w kontrolerze aktualną wagę z bazy
    _weightController = TextEditingController(text: widget.car.weightKg.toString());
    
    // Domyślne wartości pogodowe na start (później można je np. pobierać z internetu)
    _tempController = TextEditingController(text: "20");
    _pressureController = TextEditingController(text: "1013");
  }

  @override
  void dispose() {
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
      // Używamy SingleChildScrollView, by klawiatura ekranowa nie zgłaszała błędów "overflow"
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SEKCJA 1: PARAMETRY POJAZDU (Zapisywane w bazie)
            const Text("Parametry pojazdu:", style: TextStyle(fontSize: 18, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Waga (kg) = Auto + Kierowca + Paliwo",
                border: OutlineInputBorder(),
                suffixText: "kg",
                prefixIcon: Icon(Icons.monitor_weight),
              ),
              onChanged: (val) {
                // Zapisujemy wagę w locie do bazy przy każdej zmianie
                double? newWeight = double.tryParse(val);
                if (newWeight != null) {
                  widget.car.weightKg = newWeight;
                  dbService.saveCar(widget.car); 
                }
              },
            ),
            
            const SizedBox(height: 30),

            // SEKCJA 2: WARUNKI ATMOSFERYCZNE (Tymczasowe dla sesji)
            const Text("Warunki do korekcji (Norma DIN):", style: TextStyle(fontSize: 18, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tempController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Temperatura",
                      border: OutlineInputBorder(),
                      suffixText: "°C",
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
                      labelText: "Ciśnienie",
                      border: OutlineInputBorder(),
                      suffixText: "hPa",
                      prefixIcon: Icon(Icons.speed), // Używamy ikony speed jako barometru
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),
            
            // PANEL INFORMACYJNY
            Card(
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blueAccent, size: 30),
                    SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        "Dokładna waga to klucz do poprawnego pomiaru (błąd 50kg to ok. 3-5% przekłamania wyniku). Temperatura i ciśnienie posłużą do korekcji wyników wg normy DIN 70020.",
                        style: TextStyle(height: 1.4),
                      )
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}