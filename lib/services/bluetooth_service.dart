import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class AppBleService {
  static const String serviceUuid = "19b10000-e8f2-537e-4f6c-d104768a1214";
  static const String characteristicUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";

  fbp.BluetoothDevice? _device;
  StreamSubscription? _lastSubscription;
  
  final StreamController<double> _speedController = StreamController<double>.broadcast();
  Stream<double> get speedStream => _speedController.stream;

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  // NOWE: Strumienie dla satelitów i statusu GPS
  final StreamController<int> _satellitesController = StreamController<int>.broadcast();
  Stream<int> get satellitesStream => _satellitesController.stream;

  bool isConnected = false;

  Future<void> connectToDevice() async {
    _connectionController.add(false);
    await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    fbp.FlutterBluePlus.scanResults.listen((results) async {
      for (fbp.ScanResult r in results) {
        if (r.device.platformName == "Dyno-ESP32") {
          _device = r.device;
          await fbp.FlutterBluePlus.stopScan();
          
          try {
            await _device!.connect();
            isConnected = true;
            _connectionController.add(true);
            _setupNotifications();
          } catch (e) {
            _connectionController.add(false);
          }
          break;
        }
      }
    });
  }

  void _setupNotifications() async {
    if (_device == null) return;

    List<fbp.BluetoothService> services = await _device!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == characteristicUuid) {
            await characteristic.setNotifyValue(true);
            
            _lastSubscription = characteristic.lastValueStream.listen((value) {
              if (value.isEmpty) return;
              
              String rawData = utf8.decode(value);
              // Rozbijamy ramkę "speed;sats;fix"
              List<String> parts = rawData.split(';');
              
              if (parts.length >= 2) {
                double? speed = double.tryParse(parts[0]);
                int? sats = int.tryParse(parts[1]);
                
                if (speed != null) _speedController.add(speed);
                if (sats != null) _satellitesController.add(sats);
              }
            });
          }
        }
      }
    }
  }

  void dispose() {
    _lastSubscription?.cancel();
    _device?.disconnect();
    _speedController.close();
    _connectionController.close();
    _satellitesController.close();
  }
}