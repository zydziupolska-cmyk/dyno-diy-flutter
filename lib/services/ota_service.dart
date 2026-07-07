import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Status aktualizacji OTA
enum OtaStatus { idle, connecting, uploading, verifying, success, error }

/// Postęp OTA — emitowany na strumieniu progressStream
class OtaProgress {
  final OtaStatus status;
  final double percent;    // 0.0 – 1.0
  final int bytesSent;
  final int bytesTotal;
  final String? message;
  final String? error;
  
  OtaProgress({
    required this.status,
    this.percent = 0,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.message,
    this.error,
  });
}

/// Serwis do aktualizacji firmware ESP32 przez BLE (OTA).
///
/// Protokół:
///   1. Połącz się z ESP32 (lub użyj istniejącego połączenia)
///   2. Wyślij "BEGIN:rozmiar" do OTA_CONTROL
///   3. Wyślij bajty .bin w chunkach do OTA_DATA
///   4. Wyślij "END" do OTA_CONTROL
///   5. ESP32 restartuje się automatycznie z nowym firmware
///
/// Postęp jest raportowany przez [progressStream].
class OtaService {
  // UUID muszą być identyczne z firmware!
  static const String otaServiceUuid = "19b10000-e8f2-537e-4f6c-d104768a1215";
  static const String otaControlUuid = "19b10001-e8f2-537e-4f6c-d104768a1215";
  static const String otaDataUuid    = "19b10002-e8f2-537e-4f6c-d104768a1215";

  final _progressController = StreamController<OtaProgress>.broadcast();
  Stream<OtaProgress> get progressStream => _progressController.stream;

  bool _uploading = false;
  bool get isUploading => _uploading;

  /// Pobierz wersję firmware z połączonego ESP32.
  /// Wymaga, żeby urządzenie było już połączone.
  Future<String?> getFirmwareVersion(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != otaServiceUuid) continue;
        for (final ch in svc.characteristics) {
          if (ch.uuid.toString().toLowerCase() == otaControlUuid) {
            final val = await ch.read();
            if (val.isNotEmpty) {
              return String.fromCharCodes(val).trim();
            }
          }
        }
      }
    } catch (e) {
      print('[OTA] Błąd odczytu wersji: $e');
    }
    return null;
  }

  /// Wyślij firmware (.bin) do ESP32.
  /// [device] — połączone urządzenie BLE (to samo co do GPS).
  /// [firmwareBytes] — zawartość pliku .bin (skompilowany firmware).
  Future<bool> uploadFirmware(
      BluetoothDevice device, Uint8List firmwareBytes) async {
    if (_uploading) {
      _emit(OtaStatus.error, error: 'Aktualizacja już w toku');
      return false;
    }

    _uploading = true;
    _emit(OtaStatus.connecting, message: 'Szukam serwisu OTA...');

    BluetoothCharacteristic? controlChar;
    BluetoothCharacteristic? dataChar;
    StreamSubscription? notifySub;

    try {
      // ── Znajdź charakterystyki OTA ──
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != otaServiceUuid) continue;
        for (final ch in svc.characteristics) {
          final uuid = ch.uuid.toString().toLowerCase();
          if (uuid == otaControlUuid) controlChar = ch;
          if (uuid == otaDataUuid) dataChar = ch;
        }
      }

      if (controlChar == null || dataChar == null) {
        _emit(OtaStatus.error,
            error: 'ESP32 nie ma serwisu OTA. Wgraj firmware z OTA przez USB pierwszy raz.');
        _uploading = false;
        return false;
      }

      // ── Nasłuchuj odpowiedzi z ESP32 ──
      await controlChar.setNotifyValue(true);
      
      final completer = Completer<bool>();
      String lastResponse = '';

      notifySub = controlChar.onValueReceived.listen((value) {
        if (value.isEmpty) return;
        lastResponse = String.fromCharCodes(value).trim();
        print('[OTA] <- $lastResponse');

        if (lastResponse.startsWith('OK:END')) {
          _emit(OtaStatus.success,
              message: 'Firmware zaktualizowany! ESP32 restartuje się...',
              percent: 1.0,
              sent: firmwareBytes.length,
              total: firmwareBytes.length);
          if (!completer.isCompleted) completer.complete(true);
        } else if (lastResponse.startsWith('ERR:')) {
          _emit(OtaStatus.error, error: 'ESP32: $lastResponse');
          if (!completer.isCompleted) completer.complete(false);
        } else if (lastResponse.startsWith('OK:') && lastResponse != 'OK:BEGIN') {
          // Potwierdzenie postępu: "OK:bytesReceived"
          final received = int.tryParse(lastResponse.substring(3)) ?? 0;
          if (received > 0 && firmwareBytes.length > 0) {
            _emit(OtaStatus.uploading,
                percent: received / firmwareBytes.length,
                sent: received,
                total: firmwareBytes.length,
                message: '${(received * 100 / firmwareBytes.length).toStringAsFixed(0)}%');
          }
        }
      });

      // ── Negocjuj MTU ──
      // Większy MTU = większe chunki = szybszy transfer
      int mtu = await device.requestMtu(512);
      final chunkSize = mtu - 3; // 3 bajty nagłówka ATT
      print('[OTA] MTU=$mtu, chunk=$chunkSize bajtów');

      // ── BEGIN ──
      _emit(OtaStatus.uploading,
          message: 'Rozpoczynam... (${(firmwareBytes.length / 1024).toStringAsFixed(0)} KB)',
          total: firmwareBytes.length);
      
      await controlChar.write(
          'BEGIN:${firmwareBytes.length}'.codeUnits,
          withoutResponse: false);
      
      // Czekaj na OK:BEGIN
      await Future.delayed(const Duration(milliseconds: 300));
      if (lastResponse.startsWith('ERR:')) {
        _uploading = false;
        return false;
      }

      // ── WYSYŁKA CHUNKÓW ──
      int offset = 0;
      int chunkNum = 0;
      while (offset < firmwareBytes.length) {
        final end = (offset + chunkSize).clamp(0, firmwareBytes.length);
        final chunk = firmwareBytes.sublist(offset, end);

        // writeWithoutResponse jest ~3× szybsze niż write z potwierdzeniem
        await dataChar.write(chunk.toList(), withoutResponse: true);

        offset = end;
        chunkNum++;

        // Aktualizuj UI co 5 chunków
        if (chunkNum % 5 == 0) {
          _emit(OtaStatus.uploading,
              percent: offset / firmwareBytes.length,
              sent: offset,
              total: firmwareBytes.length,
              message: '${(offset * 100 / firmwareBytes.length).toStringAsFixed(0)}%');
          
          // Drobna pauza co 40 chunków — ESP32 potrzebuje chwili na zapis do flash
          if (chunkNum % 40 == 0) {
            await Future.delayed(const Duration(milliseconds: 30));
          }
        }
      }

      // ── END ──
      _emit(OtaStatus.verifying, message: 'Weryfikacja...',
          percent: 1.0, sent: firmwareBytes.length, total: firmwareBytes.length);
      
      await controlChar.write('END'.codeUnits, withoutResponse: false);

      // Czekaj na odpowiedź (OK:END lub ERR:)
      final result = await completer.future
          .timeout(const Duration(seconds: 10), onTimeout: () {
        _emit(OtaStatus.error, error: 'Timeout — brak odpowiedzi z ESP32');
        return false;
      });

      _uploading = false;
      return result;

    } catch (e) {
      _emit(OtaStatus.error, error: 'Błąd: $e');
      // Spróbuj anulować po stronie ESP32
      try {
        if (controlChar != null) {
          await controlChar.write('ABORT'.codeUnits, withoutResponse: false);
        }
      } catch (_) {}
      _uploading = false;
      return false;
    } finally {
      notifySub?.cancel();
    }
  }

  /// Anuluj trwającą aktualizację
  Future<void> abort(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != otaServiceUuid) continue;
        for (final ch in svc.characteristics) {
          if (ch.uuid.toString().toLowerCase() == otaControlUuid) {
            await ch.write('ABORT'.codeUnits, withoutResponse: false);
            break;
          }
        }
      }
    } catch (e) {
      print('[OTA] Błąd abort: $e');
    }
    _uploading = false;
    _emit(OtaStatus.idle, message: 'Anulowano');
  }

  void _emit(OtaStatus status, {
    double percent = 0,
    int sent = 0,
    int total = 0,
    String? message,
    String? error,
  }) {
    _progressController.add(OtaProgress(
      status: status,
      percent: percent,
      bytesSent: sent,
      bytesTotal: total,
      message: message,
      error: error,
    ));
  }

  void dispose() {
    _progressController.close();
  }
}