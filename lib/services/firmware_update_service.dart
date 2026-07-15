import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class FirmwareInfo {
  final String version;
  final String changelog;
  final String url;
  final int    size;

  const FirmwareInfo({
    required this.version,
    required this.changelog,
    required this.url,
    required this.size,
  });
}

class FirmwareUpdateService {
  static const _base = 'https://dynomic.pro';

  /// Sprawdza czy jest nowszy firmware niż currentVersion.
  /// Zwraca FirmwareInfo jeśli dostępna aktualizacja, null jeśli aktualny.
  Future<FirmwareInfo?> checkForUpdate(String currentVersion) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/api/firmware/latest.php'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] != true) return null;

      final latestVersion = json['version'] as String;

      if (_isNewer(latestVersion, currentVersion)) {
        return FirmwareInfo(
          version:   latestVersion,
          changelog: json['changelog'] ?? '',
          url:       json['url'] as String,
          size:      json['size'] as int? ?? 0,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Porównuje wersje semantyczne (major.minor.patch)
  bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Pobiera plik .bin z serwera, zwraca bajty
  Future<List<int>?> downloadFirmware(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}