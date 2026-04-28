import 'package:flutter/material.dart';
import 'screens/garage_screen.dart';
import 'screens/calibration_screen.dart';
import 'screens/dyno_screen.dart';
import 'screens/history_screen.dart';
import 'screens/add_car_screen.dart';
import 'services/database_service.dart';
import 'models/car_profile.dart';
import 'services/bluetooth_service.dart';

// Globalny pilot do bazy danych
final dbService = DatabaseService();
final btService = AppBleService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dbService.init(); // Odpalamy bazę przed startem aplikacji
  runApp(const DynoApp());
}

class DynoApp extends StatelessWidget {
  const DynoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dyno DIY',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const MainMenuScreen(),
    );
  }
}

// ---------------------------------------------------------
// MENU GŁÓWNE Z PODŁĄCZONĄ BAZĄ DANYCH
// ---------------------------------------------------------
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dyno DIY - Start', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PANEL STATUSU SPRZĘTU
StreamBuilder<bool>(
  stream: btService.connectionStream,
  initialData: false,
  builder: (context, snapshot) {
    bool connected = snapshot.data ?? false;
    Color statusColor = connected ? Colors.green : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: statusColor,
            size: 40,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Moduł ESP32-M9N', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              
              // --- DYNAMICZNA SEKCJA SATELITÓW ---
              if (!connected)
                const Text('Brak połączenia', style: TextStyle(color: Colors.grey))
              else
                StreamBuilder<int>(
                  stream: btService.satellitesStream,
                  initialData: 0,
                  builder: (context, satSnapshot) {
                    int sats = satSnapshot.data ?? 0;
                    // Prosta logika: 0-3 brak fixa, 4-6 Fix 2D, >6 Fix 3D
                    String fixType = "Szukam...";
                    if (sats > 6) fixType = "Fix 3D";
                    else if (sats > 0) fixType = "Fix 2D";

                    return Text(
                      'Satelity: $sats ($fixType)',
                      style: const TextStyle(color: Colors.grey),
                    );
                  },
                ),
            ],
          ),
          const Spacer(),
          Text(
            connected ? 'POŁĄCZONO' : 'ROZŁĄCZONO',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  },
),
      
            const SizedBox(height: 30),
            const Text('Twoja Flota (Wybierz pojazd):', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 10),

            // LISTA POJAZDÓW Z BAZY DANYCH
            Expanded(
              child: FutureBuilder<List<CarProfile>>(
                future: dbService.getAllCars(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
                  }
                  
                  final cars = snapshot.data ?? [];

                  if (cars.isEmpty) {
                    return const Center(child: Text('Brak aut w garażu. Dodaj pierwsze!', style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    itemCount: cars.length,
                    itemBuilder: (context, index) {
                      final car = cars[index];
                      return Card(
                        color: Colors.grey[850],
                        child: ListTile(
                          leading: const Icon(Icons.directions_car, size: 40, color: Colors.white),
                          title: Text(car.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          
                          // ZMIANA: Usunięta waga. Zostawiamy tylko rejestrację i typ skrzyni biegów
                          subtitle: Text('${car.licensePlate ?? "Brak nr rej."} | ${car.transmission.name}'),
                          
                          // PRZYCISK USUWANIA (Z ALERTEM)
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    backgroundColor: Colors.grey[900],
                                    title: const Text('Usuń pojazd', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    content: Text(
                                      'Czy na pewno chcesz usunąć pojazd "${car.name}"?\nTej operacji nie można cofnąć.',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('ANULUJ', style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text('USUŃ', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirm == true) {
                                await dbService.deleteCar(car.id);
                                setState(() {}); 
                              }
                            },
                          ),
                          onTap: () {
                            // Przechodzimy do sesji, zabierając ze sobą auto
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (context) => SessionNavigation(car: car))
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // PRZYCISK DODAWANIA NOWEGO AUTA
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final newCar = await Navigator.push<CarProfile>(
            context,
            MaterialPageRoute(builder: (context) => const AddCarScreen()),
          );

          if (newCar != null) {
            await dbService.saveCar(newCar);
            setState(() {}); 
          }
        },
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('DODAJ AUTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ---------------------------------------------------------
// NAWIGACJA SESJI
// ---------------------------------------------------------
class SessionNavigation extends StatefulWidget {
  final CarProfile car; // Klasa przyjmuje auto!

  const SessionNavigation({super.key, required this.car});

  @override
  State<SessionNavigation> createState() => _SessionNavigationState();
}

class _SessionNavigationState extends State<SessionNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Listę ekranów przenosimy tutaj, żeby mogła "widzieć" widget.car
    final List<Widget> screens = [
      GarageScreen(car: widget.car), // Przekazujemy auto do Garażu, gdzie ustalamy wagę
      const CalibrationScreen(),
      const DynoScreen(),
      const HistoryScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ustawienia'),
          BottomNavigationBarItem(icon: Icon(Icons.sync), label: 'Kalibracja'),
          BottomNavigationBarItem(icon: Icon(Icons.speed), label: 'Pomiar'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Archiwum'),
        ],
      ),
    );
  }
}