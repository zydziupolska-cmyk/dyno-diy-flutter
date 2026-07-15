import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/garage_screen.dart';
import 'screens/calibration_screen.dart';
import 'screens/prelaunch_screen.dart';
import 'screens/history_screen.dart';
import 'screens/add_car_screen.dart';
import 'screens/workshop_settings_screen.dart';
import 'screens/gps_diagnostics_screen.dart';
import 'screens/ota_update_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'services/database_service.dart';
import 'services/bluetooth_service.dart';
import 'services/auth_service.dart';
import 'services/measurement_upload_service.dart';
import 'services/firmware_update_service.dart';
import 'models/car_profile.dart';

final dbService   = DatabaseService();
final btService   = AppBleService();
final authService = AuthService();
final navigatorKey = GlobalKey<NavigatorState>();

// Cache danych sesji pomiaru – przeżywa rebuild zakładek
final Map<int, Map<String, double>> sessionCache = {};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dbService.init();

  // Wczytaj zapisaną sesję (token, user, licencja z secure storage)
  await authService.init();

  // Podepnij AuthService do BLE — potrzebny do handshake licencyjnego
  btService.setAuthService(authService);
  // Powiadom użytkownika gdy ESP32 nie należy do jego konta
  btService.setSerialMismatchCallback((serial) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Device not yours',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This ESP32 (serial: ${serial.substring(0, 8)}…) '
          'is not linked to your account.\n\n'
          'If you purchased this device, contact support to transfer it.',
          style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('OK',
                style: TextStyle(color: const Color(0xFFE51C1C)))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
            },
            child: const Text('Contact support',
                style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  });

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
      navigatorKey: navigatorKey,
      title: 'Dynomic',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0d0d0d),
        colorScheme: const ColorScheme.dark(
          primary:   Color(0xFFE51C1C),
          secondary: Color(0xFFE51C1C),
          surface:   Color(0xFF111111),
          error:     Color(0xFFE51C1C),
        ),
        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor:  Color(0xFF0d0d0d),
          foregroundColor:  Colors.white,
          elevation:        0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Color(0xFF888888)),
          actionsIconTheme: IconThemeData(color: Color(0xFF888888)),
        ),
        // BottomNavigationBar
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor:     Color(0xFF0d0d0d),
          selectedItemColor:   Color(0xFFE51C1C),
          unselectedItemColor: Color(0xFF444444),
          type:                BottomNavigationBarType.fixed,
          selectedLabelStyle:  TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          unselectedLabelStyle:TextStyle(fontSize: 10),
          elevation: 0,
        ),
        // Karty
        cardTheme: const CardThemeData(
          color:  Color(0xFF111111),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0xFF1e1e1e)),
          ),
        ),
        // Przyciski
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE51C1C),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE51C1C),
            side: const BorderSide(color: Color(0xFFE51C1C)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE51C1C),
          ),
        ),
        // InputDecoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141414),
          labelStyle: const TextStyle(color: Color(0xFF666666)),
          hintStyle: const TextStyle(color: Color(0xFF444444)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1e1e1e)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1e1e1e)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE51C1C), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
        // Divider
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1e1e1e),
          thickness: 0.5,
        ),
        // Text
        textTheme: const TextTheme(
          bodyLarge:   TextStyle(color: Colors.white),
          bodyMedium:  TextStyle(color: Color(0xFFBBBBBB)),
          bodySmall:   TextStyle(color: Color(0xFF666666)),
          titleLarge:  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          labelSmall:  TextStyle(color: Color(0xFF555555), fontSize: 10),
        ),
        // SnackBar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1a1a1a),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
        ),
        // Switch/Checkbox
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? const Color(0xFFE51C1C)
                  : const Color(0xFF444444)),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? const Color(0xFFE51C1C).withValues(alpha: 0.3)
                  : const Color(0xFF222222)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Bramka: pokazuje ekran logowania gdy user niezalogowany,
/// onboarding przy pierwszym uruchomieniu, główne menu gdy zalogowany.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _onboardingDone = true; // domyślnie true — czekamy na odczyt
  bool _checkingPrefs  = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done  = prefs.getBool('onboarding_done') ?? false;
    if (mounted) setState(() {
      _onboardingDone = done;
      _checkingPrefs  = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Ładowanie prefs lub auth
    if (_checkingPrefs || !auth.initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0d0d0d),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE51C1C)),
        ),
      );
    }

    // Pierwsze uruchomienie — pokaż onboarding
    if (!_onboardingDone) {
      return OnboardingScreen(
        onDone: () => setState(() => _onboardingDone = true),
      );
    }

    if (!auth.isLoggedIn) {
      dbService.setUserId(0);
      return const AuthScreen();
    }

    if (auth.user != null) {
      dbService.setUserId(auth.user!.id);
    }

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
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    // Sprawdź firmware gdy ESP32 się połączy
    _connSub = btService.connectionStream.listen((connected) {
      if (connected && mounted) {
        _checkFirmwareUpdate();
      }
    });
    // Sprawdź też od razu jeśli już połączony
    if (btService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirmwareUpdate());
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _checkFirmwareUpdate() async {
    if (!mounted) return;
    // Poczekaj chwilę żeby BLE się ustabilizowało
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted || !btService.isConnected) return;

    // Odczytaj wersję firmware z ESP32 przez BLE
    final currentVersion = await btService.readFirmwareVersion();
    debugPrint('[MAIN] ESP32 firmware: $currentVersion');

    final svc    = FirmwareUpdateService();
    final update = await svc.checkForUpdate(currentVersion ?? '0.0.0');
    if (!mounted || update == null) return;

    ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firmware update available: v${update.version}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ),
          if (update.changelog.isNotEmpty)
            Text(update.changelog,
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
      ),
      leading: const Icon(Icons.system_update, color: Colors.greenAccent),
      backgroundColor: const Color(0xFF0d1f0d),
      actions: [
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const OtaUpdateScreen()));
          },
          child: const Text('Update now',
              style: TextStyle(
                  color: Colors.greenAccent, fontWeight: FontWeight.bold)),
        ),
        TextButton(
          onPressed: () =>
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
          child: const Text('Later',
              style: TextStyle(color: Colors.grey)),
        ),
      ],
    ));
  }

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
        title: Row(
          children: [
            // Logo SVG Dynomic
            SizedBox(
              width: 26, height: 26,
              child: CustomPaint(painter: _DynomicLogoPainter()),
            ),
            const SizedBox(width: 8),
            const Text('Dynomic',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt, size: 20),
            tooltip: 'Firmware update',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OtaUpdateScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.business_outlined, size: 20),
            tooltip: 'Workshop settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const WorkshopSettingsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Log out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Log out',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                      'Are you sure you want to log out?',
                      style: TextStyle(color: Colors.grey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Log out',
                          style: TextStyle(color: const Color(0xFFE51C1C))),
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
    Color statusColor = connected ? Colors.green : const Color(0xFFE51C1C);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1e1e1e)),
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
                child: const Text('ESP32-M9N Module',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              
              // --- DYNAMICZNA SEKCJA SATELITÓW ---
              if (!connected)
                const Text('No connection', style: TextStyle(color: Colors.grey))
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
              child: const Text('Connect', style: TextStyle(fontSize: 14)),
            )
          else
            Text(
              'CONNECTED',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  },
),
      
            const SizedBox(height: 30),
            const Text('Your Fleet (Select a vehicle):', style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 10),

            // LISTA POJAZDÓW Z BAZY DANYCH
            Expanded(
              child: FutureBuilder<List<CarProfile>>(
                future: dbService.getAllCars(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: const Color(0xFFE51C1C)));
                  }
                  
                  final cars = snapshot.data ?? [];

                  if (cars.isEmpty) {
                    return const Center(child: Text('No cars in the garage. Add the first one!', style: TextStyle(color: Colors.grey)));
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
                            icon: const Icon(Icons.delete_outline, color: const Color(0xFFE51C1C)),
                            onPressed: () async {
                              final bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF111111),
                                    title: const Text('Delete Vehicle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    content: Text(
                                      'Are you sure you want to delete the vehicle "${car.name}"?\nThis action cannot be undone.',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE51C1C)),
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text('DELETE', style: TextStyle(color: Colors.white)),
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
      floatingActionButton: FloatingActionButton(
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
        backgroundColor: const Color(0xFFE51C1C),
        foregroundColor: Colors.white,
        elevation: 0,
        child: const Icon(Icons.add, size: 26),
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0d0d0d),
          border: Border(top: BorderSide(color: Color(0xFF1e1e1e), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_car_outlined),
              activeIcon: Icon(Icons.directions_car),
              label: 'Vehicle',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_outlined),
              activeIcon: Icon(Icons.tune),
              label: 'Calibrate',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.timer_outlined),
              activeIcon: Icon(Icons.timer),
              label: 'Run',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart_outlined),
              activeIcon: Icon(Icons.show_chart),
              label: 'History',
            ),
          ],
        ),
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

/// Logo Dynomic z formatu SVG 
class _DynomicLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Skalowanie płótna z oryginalnego wymiaru 28x28 na docelowy wymiar widgetu (np. 26x26)
    final double scaleX = size.width / 28.0;
    final double scaleY = size.height / 28.0;
    canvas.scale(scaleX, scaleY);

    // Wspólne ustawienia pędzla (odpowiadają za atrybuty 'stroke' z SVG)
    final Paint paint = Paint()
      ..color = const Color(0xFFE51C1C) // HEX #E51C1C (0xFF to 100% nieprzezroczystości)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round   // stroke-linecap="round"
      ..strokeJoin = StrokeJoin.round; // stroke-linejoin="round"

    // 1. Rysowanie okręgu: <circle cx="14" cy="14" r="13" />
    canvas.drawCircle(const Offset(14, 14), 13, paint);

    // 2. Rysowanie ścieżki (zygzak): <path d="M7 14 L11 10 L14 16 L18 8 L21 14" />
    final Path path = Path()
      ..moveTo(7, 14)  // M7 14
      ..lineTo(11, 10) // L11 10
      ..lineTo(14, 16) // L14 16
      ..lineTo(18, 8)  // L18 8
      ..lineTo(21, 14); // L21 14

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // Logo jest statyczne, więc nie ma potrzeby przerysowywania przy aktualizacjach stanu
    return false;
  }
}