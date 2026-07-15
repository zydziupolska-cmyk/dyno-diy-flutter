import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'database_service.dart';
import '../models/car_profile.dart';

/// Generuje kompaktowy XML z punktów wykresu
String _buildXml(DynoRun run) {
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<DynoRun>');
  buf.writeln('  <MaxHp>${run.maxEngineHp.toStringAsFixed(2)}</MaxHp>');
  buf.writeln('  <MaxNm>${run.maxEngineTorque.toStringAsFixed(2)}</MaxNm>');
  buf.writeln('  <WeightKg>${run.sessionWeightKg.toStringAsFixed(1)}</WeightKg>');
  buf.writeln('  <Correction>${run.correctionFactor.toStringAsFixed(6)}</Correction>');
  buf.writeln('  <DataPoints count="${run.graphDataPoints.length}">');
  for (final pt in run.graphDataPoints) {
    final parts = pt.split(';');
    if (parts.length >= 2) {
      final speed = parts[0];
      final hp    = parts[1];
      final nm    = parts.length >= 3 ? parts[2] : '';
      buf.write('    <P s="$speed" h="$hp"');
      if (nm.isNotEmpty && nm != '0') buf.write(' n="$nm"');
      buf.writeln('/>');
    }
  }
  buf.writeln('  </DataPoints>');
  buf.writeln('</DynoRun>');
  return buf.toString();
}

/// Serwis do wysyłania pomiarów na serwer gdy user ma włączony cloud sync.
class MeasurementUploadService {
  static const String _baseUrl = 'https://dynomic.pro';

  final AuthService _auth;
  MeasurementUploadService(this._auth);

  /// Wysyła wynik pomiaru na serwer z pełnym XML danych wykresu.
  Future<bool> upload({
    required double maxHp,
    required double maxNm,
    required double weightKg,
    required double correction,
    required DateTime measuredAt,
    String? vehicleName,
    String? licencePlate,
    DynoRun? run,
    String? xmlData,
  }) async {
    if (!_auth.isLoggedIn) {
      debugPrint('[UPLOAD] Pominięto — user niezalogowany');
      return false;
    }
    if (_auth.user?.measurementsUpload != true) {
      debugPrint('[UPLOAD] Pominięto — cloud sync wyłączony');
      return false;
    }

    final xml = xmlData ?? (run != null ? _buildXml(run) : null);
    debugPrint('[UPLOAD] XML: ${xml != null ? "${xml.length} bajtów" : "brak"}');
    debugPrint('[UPLOAD] Vehicle: $vehicleName ($licencePlate)');

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/measurements/upload.php'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ${_auth.token ?? ""}',
        },
        body: jsonEncode({
          'measured_at': measuredAt.toUtc().toIso8601String(),
          'max_hp':      maxHp,
          'max_nm':      maxNm,
          'weight_kg':   weightKg,
          'correction':  correction,
          if (vehicleName  != null && vehicleName.isNotEmpty)
            'vehicle_name':  vehicleName,
          if (licencePlate != null && licencePlate.isNotEmpty)
            'licence_plate': licencePlate,
          if (xml != null) 'xml_data': xml,
        }),
      ).timeout(const Duration(seconds: 20));

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] == true) {
        debugPrint('[UPLOAD] ✓ Pomiar zapisany w chmurze (id=${json['id']})');
        return true;
      } else {
        debugPrint('[UPLOAD] ✗ HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[UPLOAD] ✗ Błąd sieci: $e');
      return false;
    }
  }

  /// Synchronizuje wszystkie lokalne pomiary niezsynkowane z chmurą.
  Future<void> syncPending(DatabaseService db) async {
    if (!_auth.isLoggedIn || _auth.user?.measurementsUpload != true) return;

    final unsynced = await db.getUnsyncedRuns();
    if (unsynced.isEmpty) return;

    debugPrint('[SYNC] Znaleziono ${unsynced.length} niezsynkowanych pomiarów');

    // Pobierz wszystkie samochody raz
    final cars = await db.getAllCars();
    final carMap = { for (final c in cars) c.id: c };

    int ok = 0;
    for (final run in unsynced) {
      final car = carMap[run.carId];
      final success = await upload(
        maxHp:        run.maxEngineHp,
        maxNm:        run.maxEngineTorque,
        weightKg:     run.sessionWeightKg,
        correction:   run.correctionFactor,
        measuredAt:   run.timestamp,
        vehicleName:  car?.name,
        licencePlate: car?.licensePlate,
        run:          run,
      );
      if (success && run.id > 0) {
        await db.markRunSynced(run.id);
        ok++;
      }
    }
    debugPrint('[SYNC] Zsynchronizowano $ok/${unsynced.length} pomiarów');
  }
}