import 'package:flutter/material.dart';
import '../models/car_profile.dart';

class AddCarScreen extends StatefulWidget {
  const AddCarScreen({super.key});

  @override
  State<AddCarScreen> createState() => _AddCarScreenState();
}

class _AddCarScreenState extends State<AddCarScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _name = '';
  String _licensePlate = '';
  TransmissionType _transmission = TransmissionType.manual;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add new vehicle', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // POLE: NAZWA
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Marka i model (np. BMW E46 M3)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
                validator: (val) => val == null || val.isEmpty ? 'To pole jest wymagane' : null,
                onSaved: (val) => _name = val!,
              ),
              const SizedBox(height: 16),

              // POLE: REJESTRACJA
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Numer rejestracyjny (opcjonalnie)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                textCapitalization: TextCapitalization.characters,
                onSaved: (val) => _licensePlate = val ?? '',
              ),
              const SizedBox(height: 16),

              // POLE: SKRZYNIA BIEGÓW I NAPĘD
              DropdownButtonFormField<TransmissionType>(
                decoration: const InputDecoration(
                  labelText: 'Rodzaj napędu / Skrzynia',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings),
                ),
                initialValue: _transmission, 
                items: const [
                  DropdownMenuItem(value: TransmissionType.manual, child: Text('Manual (RWD/FWD)')),
                  DropdownMenuItem(value: TransmissionType.automatic, child: Text('Automatic (RWD/FWD)')),
                  DropdownMenuItem(value: TransmissionType.awdManual, child: Text('Manual (AWD/4WD)')),
                  DropdownMenuItem(value: TransmissionType.awdAutomatic, child: Text('Automatic (AWD/4WD)')),
                ],
                onChanged: (val) {
                  setState(() {
                    if (val != null) _transmission = val;
                  });
                },
              ),
              
              const SizedBox(height: 32),

              // PRZYCISK ZAPISU
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    
                    double baseLoss = 0.15;
                    if (_transmission == TransmissionType.automatic) baseLoss = 0.18;
                    if (_transmission == TransmissionType.awdManual) baseLoss = 0.20;
                    if (_transmission == TransmissionType.awdAutomatic) baseLoss = 0.22;

                    final newCar = CarProfile(
                      name: _name,
                      licensePlate: _licensePlate.isEmpty ? null : _licensePlate,
                      weightKg: 1500.0, 
                      area: 2.2, 
                      cd: 0.3,   
                      lossDrivetrain: baseLoss,
                      transmission: _transmission,
                    );

                    Navigator.pop(context, newCar);
                  }
                },
                child: const Text('ADD TO GARAGE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              )
            ],
          ),
        ),
      ),
    );
  }
}