import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'auth_service.dart';
import 'license_service.dart';

/// Jedna atomowa ramka odebrana z ESP32: prędkość + satelity + znacznik
/// czasu ESP32 (millis() w chwili sparsowania tej epoki GPS).
/// gpsTimeMs pochodzi z zegara ESP32, NIE z czasu odebrania pakietu BLE.
class GpsFrame {
  final double speed;
  final int sats;
  final int? gpsTimeMs;
  GpsFrame({required this.speed, required this.sats, this.gpsTimeMs});
}

/// Status licencji BLE — emitowany na licenseStatusStream
enum BleAuthState {
  unknown,        // przed handshake
  verifying,      // handshake w toku
  authorized,     // licencja zaakceptowana przez ESP32
  unauthorized,   // odmowa (zły serial / właściciel / podpis)
  noLicense,      // aplikacja nie ma licencji (user niezalogowany)
  notSupported,   // stary firmware bez serwisu licencji
}

class AppBleService {
  static const String serviceUuid        = "19b10000-e8f2-537e-4f6c-d104768a1214";
  static const String characteristicUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";

  // AuthService jest wstrzykiwany po inicjalizacji (unika circular dependency)
  AuthService? _authService;
  void setAuthService(AuthService auth) => _authService = auth;

  /// Callback wywoływany gdy serial ESP32 nie pasuje do konta
  Function(String serial)? _onSerialMismatch;
  void setSerialMismatchCallback(Function(String serial) cb) {
    _onSerialMismatch = cb;
  }

  /// Odczytuje serial urządzenia z LIC_SERIAL_UUID
  Future<String?> _readDeviceSerial(BluetoothDevice device) async {
    const licServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1216';
    const licSerialUuid  = '19b10001-e8f2-537e-4f6c-d104768a1216';
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != licServiceUuid) continue;
        for (final ch in svc.characteristics) {
          if (ch.uuid.toString().toLowerCase() == licSerialUuid) {
            final bytes = await ch.read();
            if (bytes.isNotEmpty) {
              return String.fromCharCodes(bytes).trim();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] readDeviceSerial error: $e');
    }
    return null;
  }

  BluetoothDevice? _device;
  BluetoothDevice? get currentDevice => _device;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>?        _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final _speedController      = StreamController<double>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _satellitesController = StreamController<int>.broadcast();
  final _gpsTimeController    = StreamController<int>.broadcast();
  final _frameController      = StreamController<GpsFrame>.broadcast();
  final _authStateController  = StreamController<BleAuthState>.broadcast();

  Stream<double>       get speedStream       => _speedController.stream;
  Stream<bool>         get connectionStream  => _connectionController.stream;
  Stream<int>          get satellitesStream  => _satellitesController.stream;
  Stream<int>          get gpsTimeStream     => _gpsTimeController.stream;
  Stream<GpsFrame>     get frameStream       => _frameController.stream;
  Stream<BleAuthState> get licenseStatusStream => _authStateController.stream;

  int  _lastGpsTimeMs = 0;
  int  get lastGpsTimeMs => _lastGpsTimeMs;
  bool isConnected = false;
  bool _scanning   = false;
  bool _shouldReconnect = false;

  BleAuthState _authState = BleAuthState.unknown;
  BleAuthState get authState => _authState;

  void _setAuthState(BleAuthState s) {
    _authState = s;
    _authStateController.add(s);
  }

  Future<void> connectToDevice() async {
    if (_scanning || isConnected) return;

    _scanning = true;
    _shouldReconnect = true;
    _connectionController.add(false);

    await FlutterBluePlus.stopScan();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) async {
        for (final r in results) {
          if (r.device.platformName.contains("Dyno") || r.device.platformName.contains("ESP32")) {
            print('[BLE] Znaleziono: ${r.device.platformName}');
            await FlutterBluePlus.stopScan();
            _scanning = false;
            await _connectAndListen(r.device);
            break;
          }
        }
      },
      onError: (e) {
        print('[BLE] Blad skanowania: $e');
        _scanning = false;
        _connectionController.add(false);
      },
    );

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      print('[BLE] Nie mozna uruchomic skanowania: $e');
      _scanning = false;
    }
  }

  Future<void> _connectAndListen(BluetoothDevice device) async {
    _device = device;

    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      isConnected = connected;
      _connectionController.add(connected);

      if (!connected) {
        debugPrint('[BLE] Rozlaczono');
        _notifySubscription?.cancel();
        _notifySubscription = null;
        _setAuthState(BleAuthState.unknown);

        if (_shouldReconnect) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_shouldReconnect && !isConnected) connectToDevice();
          });
        }
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      debugPrint('[BLE] Polaczono z ${device.platformName}');
      await Future.delayed(const Duration(milliseconds: 500));

      // ── Weryfikacja seryjna ────────────────────────────────────
      // Sprawdź czy to urządzenie należy do zalogowanego konta.
      // Jeśli serial nie pasuje — rozłącz i powiadom użytkownika.
      final serial = await _readDeviceSerial(device);
      debugPrint('[BLE] Device serial: $serial');

      if (serial != null && _authService != null) {
        final userSerial = _authService!.license?.deviceSerial;
        if (userSerial != null &&
            serial.toUpperCase() != userSerial.toUpperCase()) {
          debugPrint('[BLE] Serial mismatch: $serial != $userSerial');
          await device.disconnect();
          isConnected = false;
          _connectionController.add(false);
          _setAuthState(BleAuthState.unauthorized);
          _onSerialMismatch?.call(serial);
          return;
        }
      }

      // ── Handshake licencyjny ───────────────────────────────────
      await _performLicenseHandshake(device);

      // Nasłuchuj GPS
      await _setupNotifications(device);
    } catch (e) {
      debugPrint('[BLE] Blad polaczenia: $e');
      isConnected = false;
      _connectionController.add(false);
    }
  }

  Future<void> _performLicenseHandshake(BluetoothDevice device) async {
    if (_authService == null) {
      debugPrint('[BLE] AuthService nie ustawiony — pomijam handshake');
      _setAuthState(BleAuthState.notSupported);
      return;
    }

    _setAuthState(BleAuthState.verifying);
    debugPrint('[BLE] Rozpoczynam handshake licencyjny...');

    final hs = LicenseHandshakeService(_authService!);
    final result = await hs.performHandshake(device);

    debugPrint('[BLE] Wynik handshake: $result');

    switch (result) {
      case LicenseResult.ok:
        _setAuthState(BleAuthState.authorized);
        break;
      case LicenseResult.notFound:
        // Stary firmware bez serwisu licencji — przepuszczamy (tryb legacy)
        debugPrint('[BLE] Stary firmware — tryb legacy (bez weryfikacji)');
        _setAuthState(BleAuthState.notSupported);
        break;
      case LicenseResult.noLicense:
        _setAuthState(BleAuthState.noLicense);
        break;
      default:
        _setAuthState(BleAuthState.unauthorized);
        break;
    }
  }

  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
              await char.setNotifyValue(true);
              print('[BLE] Notyfikacje wlaczone');

              _notifySubscription?.cancel();
              // flutter_blue_plus 1.x: char.value (nie onValueReceived)
              _notifySubscription = char.value.listen((value) {
                if (value.isNotEmpty) _parseFrame(value);
              });
              return;
            }
          }
        }
      }
      print('[BLE] Nie znaleziono serwisu/charakterystyki!');
    } catch (e) {
      print('[BLE] Blad setup: $e');
    }
  }

  // Format ramki z ESP32 (v2): "speed;sats;espMillis\n"  np. "87.4;9;123456\n"
  // (stary firmware wysyła tylko "speed;sats\n" — nadal wspierane, gpsTimeMs=null)
  void _parseFrame(List<int> rawBytes) {
    try {
      final rawData = utf8.decode(rawBytes).trim();
      print('[BLE] <- $rawData');
      final parts = rawData.split(';');

      double? speed;
      int? sats;
      int? gpsT;

      if (parts.isNotEmpty) {
        speed = double.tryParse(parts[0]);
        if (speed != null && speed >= 0) _speedController.add(speed);
      }
      if (parts.length >= 2) {
        sats = int.tryParse(parts[1]);
        if (sats != null && sats >= 0) _satellitesController.add(sats);
      }
      if (parts.length >= 3) {
        gpsT = int.tryParse(parts[2]);
        if (gpsT != null && gpsT > 0) {
          _lastGpsTimeMs = gpsT;
          _gpsTimeController.add(gpsT);
        }
      }

      if (speed != null && speed >= 0) {
        _frameController.add(GpsFrame(
          speed: speed,
          sats: sats ?? 0,
          gpsTimeMs: (gpsT != null && gpsT > 0) ? gpsT : null,
        ));
      }
    } catch (e) {
      print('[BLE] Blad parsowania: $e');
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    await _device?.disconnect();
    _device = null;
    isConnected = false;
    _scanning = false;
    _connectionController.add(false);
  }

  /// Odczytuje wersję firmware z OTA_CONTROL characteristic ESP32.
  /// Zwraca np. "4.0.0" lub null jeśli nie można odczytać.
  Future<String?> readFirmwareVersion() async {
    if (_device == null) return null;
    const otaServiceUuid  = '19b10000-e8f2-537e-4f6c-d104768a1215';
    const otaControlUuid  = '19b10001-e8f2-537e-4f6c-d104768a1215';
    try {
      final services = await _device!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != otaServiceUuid) continue;
        for (final ch in svc.characteristics) {
          if (ch.uuid.toString().toLowerCase() == otaControlUuid) {
            final bytes = await ch.read();
            if (bytes.isNotEmpty) {
              final ver = String.fromCharCodes(bytes).trim();
              if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(ver)) {
                debugPrint('[BLE] Firmware version: $ver');
                return ver;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BLE] readFirmwareVersion error: $e');
    }
    return null;
  }

  void dispose() {
    disconnect();
    _speedController.close();
    _connectionController.close();
    _satellitesController.close();
    _gpsTimeController.close();
    _frameController.close();
    _authStateController.close();
  }
}