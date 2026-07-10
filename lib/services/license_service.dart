import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'auth_service.dart';

/// Wynik weryfikacji licencji przez ESP32
enum LicenseResult {
  ok,              // 0 — autoryzowany
  badSignature,    // 1 — zły podpis
  badSerial,       // 2 — serial nie pasuje
  badOwner,        // 3 — inne konto właściciela
  parseError,      // 4 — błąd parsowania
  timeout,         // brak odpowiedzi
  noLicense,       // aplikacja nie ma licencji
  serialMismatch,  // serial urządzenia != serial w licencji (sprawdzenie po stronie app)
  notFound,        // nie znaleziono serwisu licencji (stary firmware)
}

/// Serwis obsługujący handshake licencyjny z ESP32 przez BLE.
///
/// Przepływ:
///   1. Czyta serial z ESP32 (LIC_SERIAL)
///   2. Porównuje z serialem w licencji aplikacji
///   3. Wysyła podpisaną licencję do ESP32 (LIC_SUBMIT)
///   4. ESP32 weryfikuje Ed25519 i odpowiada statusem (LIC_STATUS)
class LicenseHandshakeService {
  // UUID muszą pasować do firmware!
  static const String licServiceUuid = "19b10000-e8f2-537e-4f6c-d104768a1216";
  static const String licSerialUuid  = "19b10001-e8f2-537e-4f6c-d104768a1216";
  static const String licSubmitUuid  = "19b10002-e8f2-537e-4f6c-d104768a1216";
  static const String licStatusUuid  = "19b10003-e8f2-537e-4f6c-d104768a1216";

  final AuthService _auth;
  LicenseHandshakeService(this._auth);

  /// Wykonuje pełny handshake licencyjny.
  /// Zwraca LicenseResult.ok jeśli ESP32 autoryzował urządzenie.
  Future<LicenseResult> performHandshake(BluetoothDevice device) async {
    final license = _auth.license;
    if (license == null) {
      debugPrint('[LIC] Brak licencji w aplikacji');
      return LicenseResult.noLicense;
    }

    BluetoothCharacteristic? serialChar;
    BluetoothCharacteristic? submitChar;
    BluetoothCharacteristic? statusChar;

    try {
      // ── Znajdź charakterystyki licencji ──
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() != licServiceUuid) continue;
        for (final ch in svc.characteristics) {
          final uuid = ch.uuid.toString().toLowerCase();
          if (uuid == licSerialUuid) serialChar = ch;
          if (uuid == licSubmitUuid) submitChar = ch;
          if (uuid == licStatusUuid) statusChar = ch;
        }
      }

      if (serialChar == null || submitChar == null || statusChar == null) {
        debugPrint('[LIC] Brak serwisu licencji — stary firmware?');
        return LicenseResult.notFound;
      }

      // ── 1. Odczytaj serial z ESP32 ──
      final serialBytes = await serialChar.read();
      final deviceSerial = String.fromCharCodes(serialBytes).trim();
      debugPrint('[LIC] Serial urządzenia: $deviceSerial');

      // ── 2. Porównaj z serialem w licencji ──
      final licenseSerial = license.deviceSerial;
      if (deviceSerial != licenseSerial) {
        debugPrint('[LIC] ✗ Serial nie pasuje! Urządzenie=$deviceSerial, '
                   'licencja=$licenseSerial');
        return LicenseResult.serialMismatch;
      }
      debugPrint('[LIC] ✓ Serial zgodny z licencją');

      // ── 3. Przygotuj nasłuch statusu ──
      await statusChar.setNotifyValue(true);
      final completer = Completer<LicenseResult>();
      final sub = statusChar.onValueReceived.listen((value) {
        if (value.isEmpty) return;
        final code = int.tryParse(String.fromCharCodes(value).trim()) ?? -1;
        debugPrint('[LIC] ESP32 status: $code');
        if (!completer.isCompleted) {
          completer.complete(_codeToResult(code));
        }
      });

      // ── 4. Wyślij licencję: payload + \x00 + signature(64B) ──
      final payloadBytes   = utf8.encode(license.payload);
      final signatureBytes = base64Decode(license.signature);

      if (signatureBytes.length != 64) {
        debugPrint('[LIC] ✗ Podpis nie ma 64 bajtów: ${signatureBytes.length}');
        await sub.cancel();
        return LicenseResult.parseError;
      }

      final frame = Uint8List(payloadBytes.length + 1 + 64);
      frame.setRange(0, payloadBytes.length, payloadBytes);
      frame[payloadBytes.length] = 0; // separator \x00
      frame.setRange(payloadBytes.length + 1, frame.length, signatureBytes);

      debugPrint('[LIC] Wysyłam licencję (${frame.length} bajtów)');
      await submitChar.write(frame.toList(), withoutResponse: false);

      // ── 5. Czekaj na odpowiedź ──
      final result = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => LicenseResult.timeout,
      );

      await sub.cancel();
      return result;

    } catch (e) {
      debugPrint('[LIC] Błąd handshake: $e');
      return LicenseResult.timeout;
    }
  }

  LicenseResult _codeToResult(int code) {
    switch (code) {
      case 0:  return LicenseResult.ok;
      case 1:  return LicenseResult.badSignature;
      case 2:  return LicenseResult.badSerial;
      case 3:  return LicenseResult.badOwner;
      case 4:  return LicenseResult.parseError;
      default: return LicenseResult.timeout;
    }
  }

  /// Zwraca komunikat użytkownika dla danego wyniku
  static String messageFor(LicenseResult r) {
    switch (r) {
      case LicenseResult.ok:
        return 'Device authorized';
      case LicenseResult.noLicense:
        return 'No license found. Please log in again to download your license.';
      case LicenseResult.serialMismatch:
      case LicenseResult.badSerial:
        return 'This is not your device. It is registered to a different account.';
      case LicenseResult.badOwner:
        return 'This device is paired to another user account.';
      case LicenseResult.badSignature:
        return 'License verification failed. Please contact support.';
      case LicenseResult.parseError:
        return 'License data error. Try logging in again.';
      case LicenseResult.notFound:
        return 'Device firmware needs updating. Please update via OTA.';
      case LicenseResult.timeout:
        return 'Device did not respond. Please try reconnecting.';
    }
  }
}