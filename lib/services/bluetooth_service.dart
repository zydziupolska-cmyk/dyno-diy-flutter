import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AppBleService {
  static const String serviceUuid = "19b10000-e8f2-537e-4f6c-d104768a1214";
  static const String characteristicUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";

  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final _speedController = StreamController<double>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _satellitesController = StreamController<int>.broadcast();

  Stream<double> get speedStream => _speedController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<int> get satellitesStream => _satellitesController.stream;

  bool isConnected = false;
  bool _scanning = false;
  bool _shouldReconnect = false;

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
          if (r.device.name.contains("Dyno") || r.device.name.contains("ESP32")) {
            print('[BLE] Znaleziono: ${r.device.name}');
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
        print('[BLE] Rozlaczono');
        _notifySubscription?.cancel();
        _notifySubscription = null;

        if (_shouldReconnect) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_shouldReconnect && !isConnected) {
              connectToDevice();
            }
          });
        }
      }
    });

    try {
      // flutter_blue_plus 1.x - brak parametru license
      await device.connect(timeout: const Duration(seconds: 10));
      print('[BLE] Polaczono z ${device.name}');
      await Future.delayed(const Duration(milliseconds: 500));
      await _setupNotifications(device);
    } catch (e) {
      print('[BLE] Blad polaczenia: $e');
      isConnected = false;
      _connectionController.add(false);
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

  // Format ramki z ESP32: "speed;sats\n"  np. "87.4;9\n"
  void _parseFrame(List<int> rawBytes) {
    try {
      final rawData = utf8.decode(rawBytes).trim();
      print('[BLE] <- $rawData');
      final parts = rawData.split(';');

      if (parts.isNotEmpty) {
        final speed = double.tryParse(parts[0]);
        if (speed != null && speed >= 0) _speedController.add(speed);
      }
      if (parts.length >= 2) {
        final sats = int.tryParse(parts[1]);
        if (sats != null && sats >= 0) _satellitesController.add(sats);
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

  void dispose() {
    disconnect();
    _speedController.close();
    _connectionController.close();
    _satellitesController.close();
  }
}