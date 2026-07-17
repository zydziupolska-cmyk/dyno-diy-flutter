import 'package:flutter/material.dart';
import '../models/car_profile.dart';
import '../main.dart';
import 'dyno_screen.dart';

class PreLaunchScreen extends StatefulWidget {
  final CarProfile car;
  const PreLaunchScreen({super.key, required this.car});

  @override
  State<PreLaunchScreen> createState() => _PreLaunchScreenState();
}

// Statyczny cache — przeżywa rebuild zakładki
// klucz = carId, wartość = {weight, temp, pressure}
// Zadeklarowany globalnie w main.dart jako sessionCache

class _PreLaunchScreenState extends State<PreLaunchScreen> {
  Map<String, double>? _calibration;
  late TextEditingController _weightController;
  late TextEditingController _tempController;
  late TextEditingController _pressureController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    // Pobierz zapisane wartości lub użyj domyślnych
    final cached = sessionCache[widget.car.id];
    final weight   = cached?['weight']   ?? widget.car.weightKg;
    final temp     = cached?['temp']     ?? 20.0;
    final pressure = cached?['pressure'] ?? 1013.0;

    _weightController   = TextEditingController(text: weight.toStringAsFixed(0));
    _tempController     = TextEditingController(text: temp.toStringAsFixed(0));
    _pressureController = TextEditingController(text: pressure.toStringAsFixed(0));

    // Nasłuchuj zmian i zapisuj do cache
    _weightController.addListener(_saveToCache);
    _tempController.addListener(_saveToCache);
    _pressureController.addListener(_saveToCache);

    _loadCalibration();
  }

  void _saveToCache() {
    sessionCache[widget.car.id] = {
      'weight':   double.tryParse(_weightController.text)   ?? widget.car.weightKg,
      'temp':     double.tryParse(_tempController.text)     ?? 20.0,
      'pressure': double.tryParse(_pressureController.text) ?? 1013.0,
    };
  }

  Future<void> _loadCalibration() async {
    final cal = await dbService.getLatestCalibration(widget.car.id);
    setState(() {
      _calibration = cal;
      _loading = false;
    });
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

  // Korekcja DIN 70020
  double _calcDinCorrection() {
    final temp = double.tryParse(_tempController.text) ?? 20.0;
    final pressure = double.tryParse(_pressureController.text) ?? 1013.0;
    // Wzór DIN 70020: cf = sqrt((1013/p) * ((temp+273)/293))
    return (1013.0 / pressure) * ((temp + 273.0) / 293.0);
  }

  void _startMeasurement() {
    final weight = double.tryParse(_weightController.text) ?? widget.car.weightKg;
    final cf = _calcDinCorrection();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DynoScreen(
          car: widget.car,
          overrideWeight: weight,
          weatherCf: cf,
          kFactor: _calibration?['kFactor'],
          tempC: double.tryParse(_tempController.text),
          pressureHpa: double.tryParse(_pressureController.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cf = _calcDinCorrection();
    final bool hasCalibration = _calibration != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session data'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Auto
            _SectionHeader(title: 'Vehicle', icon: Icons.directions_car),
            const SizedBox(height: 8),
            _InfoCard(
              children: [
                _InfoRow(label: 'Name', value: widget.car.name),
                if (widget.car.licensePlate != null)
                  _InfoRow(label: 'Licence plate', value: widget.car.licensePlate!),
                _InfoRow(label: 'Drivetrain',
                    value: widget.car.transmission.name.toUpperCase()),
              ],
            ),

            const SizedBox(height: 20),

            // Waga sesji
            _SectionHeader(title: 'Session weight', icon: Icons.monitor_weight),
            const SizedBox(height: 8),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Car + Driver + Fuel',
                border: OutlineInputBorder(),
                suffixText: 'kg',
                helperText: ' Error of 50 kg = ~3% error in power',
              ),
            ),

            const SizedBox(height: 20),

            // Kalibracja k-factor
            _SectionHeader(title: 'K-Factor Calibration', icon: Icons.tune),
            const SizedBox(height: 8),
            hasCalibration
                ? _InfoCard(
                    color: Colors.greenAccent,
                    children: [
                      _InfoRow(
                          label: 'Speed @ 3 000 RPM',
                          value:
                              '${_calibration!['speedAt3000rpm']!.toStringAsFixed(1)} km/h'),
                      _InfoRow(
                          label: 'K-Factor',
                          value:
                              '${_calibration!['kFactor']!.toStringAsFixed(2)} RPM/(km/h)'),
                      _InfoRow(
                          label: 'Example',
                          value:
                              '100 km/h = ${(100 * _calibration!['kFactor']!).toStringAsFixed(0)} RPM'),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orangeAccent),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.redAccent),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Calibration required — measurement not possible.\n'
                            'Go to the Calibration tab and measure your speed at 3 000 RPM.',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  ),

            const SizedBox(height: 20),

            // Warunki atmosferyczne
            _SectionHeader(title: 'Conditions (DIN 70020 correction)', icon: Icons.thermostat),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tempController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Temperature',
                      border: OutlineInputBorder(),
                      suffixText: '°C',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pressureController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Pressure',
                      border: OutlineInputBorder(),
                      suffixText: 'hPa',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'DIN correction factor: ×${cf.toStringAsFixed(4)}',
              style: TextStyle(
                color: (cf - 1.0).abs() < 0.05 ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 30),

            // Start — zablokowany bez kalibracji
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasCalibration
                      ? Colors.greenAccent
                      : Colors.grey[800],
                  foregroundColor: hasCalibration
                      ? Colors.black
                      : Colors.grey[600],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: hasCalibration
                    ? _startMeasurement
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please calibrate first — '
                              'go to the Calibration tab'),
                            backgroundColor: Colors.redAccent,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                icon: Icon(
                  hasCalibration ? Icons.play_arrow : Icons.lock,
                  size: 30),
                label: Text(
                  hasCalibration ? 'START RUN' : 'CALIBRATION REQUIRED',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        ],
      );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final Color color;
  const _InfoCard({required this.children, this.color = Colors.grey});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}