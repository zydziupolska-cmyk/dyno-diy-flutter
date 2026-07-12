import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'database_service.dart';

/// Serwis do wysyłania pomiarów na serwer gdy user ma włączony cloud sync.
class MeasurementUploadService {
  static const String _baseUrl = 'https://dynomic.pro';

  final AuthService _auth;
  MeasurementUploadService(this._auth);

  /// Wysyła wynik pomiaru na serwer.
  /// Wywoływane automatycznie po zapisaniu pomiaru jeśli user
  /// ma włączony cloud sync (measurements_upload = true).
  ///
  /// Nie rzuca wyjątków — błędy są logowane, pomiar jest już
  /// zapisany lokalnie więc upload jest "nice to have".
  Future<bool> upload({
    required double maxHp,
    required double maxNm,
    required double weightKg,
    required double correction,
    required DateTime measuredAt,
    String? xmlData,
  }) async {
    // Sprawdź czy user jest zalogowany i ma cloud sync włączony
    if (!_auth.isLoggedIn) {
      debugPrint('[UPLOAD] Pominięto — user niezalogowany');
      return false;
    }
    if (_auth.user?.measurementsUpload != true) {
      debugPrint('[UPLOAD] Pominięto — cloud sync wyłączony');
      return false;
    }

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/measurements/upload.php'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ${_auth.token}',
        },
        body: jsonEncode({
          'measured_at': measuredAt.toUtc().toIso8601String(),
          'max_hp':      maxHp,
          'max_nm':      maxNm,
          'weight_kg':   weightKg,
          'correction':  correction,
          ...?( xmlData != null ? {'xml_data': xmlData} : null),
        }),
      ).timeout(const Duration(seconds: 15));

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] == true) {
        debugPrint('[UPLOAD] ✓ Pomiar zapisany w chmurze (id=${json['id']})');
        return true;
      } else {
        debugPrint('[UPLOAD] ✗ Błąd serwera: ${json['error']}');
        return false;
      }
    } catch (e) {
      debugPrint('[UPLOAD] ✗ Błąd sieci: $e');
      return false;
    }
  }

  /// Synchronizuje wszystkie lokalne pomiary które nie trafiły jeszcze
  /// na serwer. Wywołaj przy starcie aplikacji lub po wykryciu połączenia.
  Future<void> syncPending(DatabaseService db) async {
    if (!_auth.isLoggedIn || _auth.user?.measurementsUpload != true) return;

    final unsynced = await db.getUnsyncedRuns();
    if (unsynced.isEmpty) return;

    debugPrint('[SYNC] Znaleziono ${unsynced.length} niezsynkowanych pomiarów');

    int ok = 0;
    for (final run in unsynced) {
      final success = await upload(
        maxHp:      run.maxEngineHp,
        maxNm:      run.maxEngineTorque,
        weightKg:   run.sessionWeightKg,
        correction: run.correctionFactor,
        measuredAt: run.timestamp,
      );
      if (success && run.id > 0) {
        await db.markRunSynced(run.id);
        ok++;
      }
    }
    debugPrint('[SYNC] Zsynchronizowano $ok/${unsynced.length} pomiarów');
  }
}