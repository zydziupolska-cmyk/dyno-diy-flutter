import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'screens/garage_screen.dart';
import 'screens/calibration_screen.dart';
import 'screens/prelaunch_screen.dart';
import 'screens/history_screen.dart';
import 'screens/add_car_screen.dart';
import 'screens/workshop_settings_screen.dart';
import 'screens/gps_diagnostics_screen.dart';
import 'screens/ota_update_screen.dart';
import 'screens/auth_screen.dart';
import 'services/database_service.dart';
import 'services/bluetooth_service.dart';
import 'services/auth_service.dart';
import 'services/measurement_upload_service.dart';
import 'models/car_profile.dart';

final dbService  = DatabaseService();
final btService  = AppBleService();
final authService = AuthService();

// Cache danych sesji pomiaru – przeżywa rebuild zakładek
final Map<int, Map<String, double>> sessionCache = {};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dbService.init();

  // Wczytaj zapisaną sesję (token, user, licencja z secure storage)
  await authService.init();

  // Podepnij AuthService do BLE — potrzebny do handshake licencyjnego
  btService.setAuthService(authService);

  // Zsynchronizuj niezsynkowane pomiary w tle (nie blokuje startu)
  Future.delayed(const Duration(seconds: 3), () {
    final syncSvc = MeasurementUploadService(authService);
    syncSvc.syncPending(dbService);
  });

  // Poproś o uprawnienia Bluetooth i lokalizacji
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();

  runApp(
    ChangeNotifierProvider<AuthService>.value(
      value: authService,
      child: const DynoApp(),
    ),
  );
}

class DynoApp extends StatelessWidget {
  const DynoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dynomic',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const AuthGate(),
    );
  }
}

/// Bramka: pokazuje ekran logowania gdy user niezalogowany,
/// główne menu gdy zalogowany i ma licencję.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!auth.initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return const AuthScreen();
    }

    // Zalogowany — pokaż główne menu
    return const MainMenuScreen();
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
  int _tapCount = 0;
  DateTime? _lastTap;

  void _handleModuleTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 2) {
      _tapCount = 0; // reset po 2s przerwy
    }
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= 5) {
      _tapCount = 0;
      Navigator.push(context,
        MaterialPageRoute(builder: (_) => const GpsDiagnosticsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dynomic - Start', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt),
            tooltip: 'Aktualizacja firmware ESP32',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const OtaUpdateScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.business_outlined),
            tooltip: 'Ustawienia warsztatu',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const WorkshopSettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Wyloguj',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Wyloguj',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                      'Czy na pewno chcesz się wylogować?',
                      style: TextStyle(color: Colors.grey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Anuluj',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Wyloguj',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await authService.logout();
              }
            },
          ),
        ],
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
              GestureDetector(
                onTap: _handleModuleTap,
                child: const Text('Moduł ESP32-M9N',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              
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
                    if (sats > 6) { fixType = "Fix 3D"; }
                    else if (sats > 0) { fixType = "Fix 2D"; }

                    return Text(
                      'Satelity: $sats ($fixType)',
                      style: const TextStyle(color: Colors.grey),
                    );
                  },
                ),
            ],
          ),
          const Spacer(),
          if (!connected)
            ElevatedButton(
              onPressed: () => btService.connectToDevice(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('POŁĄCZ'),
            )
          else
            Text(
              'POŁĄCZONO',
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
      GarageScreen(car: widget.car),
      CalibrationScreen(carId: widget.car.id),
      _PomiarTab(car: widget.car),
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

// Wrapper który przed pomiarem pokazuje PreLaunchScreen z właściwym autem
class _PomiarTab extends StatelessWidget {
  final CarProfile car;
  const _PomiarTab({required this.car});

  @override
  Widget build(BuildContext context) {
    return PreLaunchScreen(car: car);
  }
}