import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AppBleService {
  static const String serviceUuid = "19b10000-e8f2-537e-4f6c-d104768a1214";
  static const String characteristicUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";
  static const String deviceName = "Dyno-ESP32";

  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // --- Strumienie danych na zewnątrz ---
  final _speedController = StreamController<double>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _satellitesController = StreamController<int>.broadcast();

  Stream<double> get speedStream => _speedController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<int> get satellitesStream => _satellitesController.stream;

  bool isConnected = false;
  bool _scanning = false;
  bool _shouldReconnect = false;

  // ------------------------------------------------------------------
  //  POŁĄCZENIE
  // ------------------------------------------------------------------
  Future<void> connectToDevice() async {
    if (_scanning || isConnected) return;

    _scanning = true;
    _shouldReconnect = true;
    _connectionController.add(false);

    await FlutterBluePlus.stopScan();

    // Słuchaj wyników skanowania
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) async {
        for (final r in results) {
          // ESP32-C3 może zmieniać nazwę lub mieć prefix
          if (r.device.platformName.contains("Dyno") || 
              r.device.platformName.contains("ESP32")) {
            
            print('[BLE] Znaleziono: ${r.device.platformName}');
            await FlutterBluePlus.stopScan();
            _scanning = false;
            await _connectAndListen(r.device);
            break;
          }
        }
      },
      onError: (e) {
        print('[BLE] Błąd skanowania: $e');
        _scanning = false;
        _connectionController.add(false);
      },
    );

    // Start skanowania (POPRAWIONE: bez parametru license)
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      print('[BLE] Nie można uruchomić skanowania: $e');
      _scanning = false;
    }

    // Cleanup po timeout
    await Future.delayed(const Duration(seconds: 16));
    if (_scanning) {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanning = false;
      print('[BLE] Timeout - nie znaleziono urządzenia');
    }
  }

  // ------------------------------------------------------------------
  //  PO ZNALEZIENIU URZĄDZENIA
  // ------------------------------------------------------------------
  Future<void> _connectAndListen(BluetoothDevice device) async {
    _device = device;

    // Obserwujemy stan połączenia - auto-reconnect przy utracie
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      isConnected = connected;
      _connectionController.add(connected);

      if (!connected) {
        print('[BLE] Rozłączono');
        _notifySubscription?.cancel();
        _notifySubscription = null;

        // Auto-reconnect jeśli było ustawione
        if (_shouldReconnect) {
          print('[BLE] Próba ponownego połączenia za 2s...');
          Future.delayed(const Duration(seconds: 2), () {
            if (_shouldReconnect && !isConnected) {
              connectToDevice();
            }
          });
        }
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
      );
      print('[BLE] Połączono z ${device.platformName}');
      
      // ESP32-C3 potrzebuje chwili po połączeniu
      await Future.delayed(const Duration(milliseconds: 500));
      await _setupNotifications(device);
    } catch (e) {
      print('[BLE] Błąd połączenia: $e');
      isConnected = false;
      _connectionController.add(false);
    }
  }

  // ------------------------------------------------------------------
  //  POWIADOMIENIA BLE
  // ------------------------------------------------------------------
  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      print('[BLE] Znaleziono ${services.length} serwisów');

      for (final service in services) {
        print('[BLE] Serwis UUID: ${service.uuid}');
        
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            print('[BLE] Char UUID: ${char.uuid}');
            
            if (char.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
              // Włącz notyfikacje
              await char.setNotifyValue(true);
              print('[BLE] Notyfikacje włączone');

              // Słuchaj świeżych danych (onValueReceived > lastValueStream)
              _notifySubscription?.cancel();
              _notifySubscription = char.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  _parseFrame(value);
                }
              });

              return;
            }
          }
        }
      }
      
      print('[BLE] Nie znaleziono odpowiedniego serwisu/charakterystyki');
    } catch (e) {
      print('[BLE] Błąd setup notyfikacji: $e');
    }
  }

  // ------------------------------------------------------------------
  //  PARSOWANIE RAMKI Z ESP32
  //
  //  Format z Arduino: "speed;sats\n"
  //  Przykład:         "87.4;9\n"
  // ------------------------------------------------------------------
  void _parseFrame(List<int> rawBytes) {
    try {
      final rawData = utf8.decode(rawBytes).trim();
      print('[BLE] <- $rawData');
      
      final parts = rawData.split(';');

      if (parts.isNotEmpty) {
        final speed = double.tryParse(parts[0]);
        if (speed != null && speed >= 0) {
          _speedController.add(speed);
        }
      }
      
      if (parts.length >= 2) {
        final sats = int.tryParse(parts[1]);
        if (sats != null && sats >= 0) {
          _satellitesController.add(sats);
        }
      }
    } catch (e) {
      print('[BLE] Błąd parsowania: $e');
    }
  }

  // ------------------------------------------------------------------
  //  ROZŁĄCZ RĘCZNIE
  // ------------------------------------------------------------------
  Future<void> disconnect() async {
    _shouldReconnect = false; // Wyłącz auto-reconnect
    
    await _scanSubscription?.cancel();
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _device?.disconnect();

    _device = null;
    isConnected = false;
    _scanning = false;
    _connectionController.add(false);
    
    print('[BLE] Rozłączono manualnie');
  }

  // ------------------------------------------------------------------
  //  SPRZĄTANIE
  // ------------------------------------------------------------------
  void dispose() {
    disconnect();
    _speedController.close();
    _connectionController.close();
    _satellitesController.close();
  }
}
