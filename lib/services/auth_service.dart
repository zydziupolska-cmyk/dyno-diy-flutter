import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Wyjątek rate limiting ────────────────────────────────────

class RateLimitedException implements Exception {
  final int retryAfterSeconds;
  const RateLimitedException(this.retryAfterSeconds);

  @override
  String toString() => 'Too many attempts. Try again in ${retryAfterSeconds}s.';
}

// ── Modele ───────────────────────────────────────────────────

class DlUser {
  final int    id;
  final String email;
  final String firstName;
  final String lastName;
  final String language;
  final bool   isAdmin;
  final bool   measurementsUpload;
  final bool   emailVerified;

  const DlUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.language,
    required this.isAdmin,
    required this.measurementsUpload,
    required this.emailVerified,
  });

  factory DlUser.fromJson(Map<String, dynamic> j) => DlUser(
    id:                  j['id']                   as int,
    email:               j['email']                as String,
    firstName:           j['first_name']           as String,
    lastName:            j['last_name']            as String,
    language:            j['language']             as String? ?? 'en',
    isAdmin:             (j['is_admin']            == true || j['is_admin']            == 1),
    measurementsUpload:  (j['measurements_upload'] == true || j['measurements_upload'] == 1),
    emailVerified:       (j['email_verified']      == true || j['email_verified']      == 1),
  );

  Map<String, dynamic> toJson() => {
    'id':                  id,
    'email':               email,
    'first_name':          firstName,
    'last_name':           lastName,
    'language':            language,
    'is_admin':            isAdmin,
    'measurements_upload': measurementsUpload,
    'email_verified':      emailVerified,
  };
}

class DlLicense {
  final String payload;
  final String signature;
  final String serverPubkey;
  final String expiresAt;

  const DlLicense({
    required this.payload,
    required this.signature,
    required this.serverPubkey,
    required this.expiresAt,
  });

  factory DlLicense.fromJson(Map<String, dynamic> j) => DlLicense(
    payload:      j['payload']       as String,
    signature:    j['signature']     as String,
    serverPubkey: j['server_pubkey'] as String,
    expiresAt:    j['expires_at']    as String,
  );

  Map<String, dynamic> toJson() => {
    'payload':       payload,
    'signature':     signature,
    'server_pubkey': serverPubkey,
    'expires_at':    expiresAt,
  };

  int? get userId {
    try {
      return (jsonDecode(payload) as Map)['userId'] as int?;
    } catch (_) { return null; }
  }

  String? get deviceSerial {
    try {
      return (jsonDecode(payload) as Map)['serial'] as String?;
    } catch (_) { return null; }
  }

  bool get isExpired {
    try {
      return DateTime.parse(expiresAt).isBefore(DateTime.now());
    } catch (_) { return true; }
  }
}

// ── AuthService ──────────────────────────────────────────────

class AuthService extends ChangeNotifier {
  static const String _baseUrl = 'https://dynomic.pro';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kToken   = 'dl_auth_token';
  static const _kUser    = 'dl_user_json';
  static const _kLicense = 'dl_license_json';

  DlUser?    _user;
  DlLicense? _license;
  String?    _token;
  String?    get token => _token;
  bool       _initialized = false;

  DlUser?    get user        => _user;
  DlLicense? get license     => _license;
  bool       get isLoggedIn  => _token != null && _user != null;
  bool       get hasLicense  => _license != null && !(_license!.isExpired);
  bool       get initialized => _initialized;

  // ── Init ────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      _token = await _storage.read(key: _kToken);
      final userJson    = await _storage.read(key: _kUser);
      final licenseJson = await _storage.read(key: _kLicense);

      if (userJson    != null) _user    = DlUser.fromJson(jsonDecode(userJson));
      if (licenseJson != null) _license = DlLicense.fromJson(jsonDecode(licenseJson));
    } catch (e) {
      debugPrint('[AuthService] init error: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  // ── Helper: sprawdź 429 przed przetworzeniem odpowiedzi ─────
  /// Rzuca [RateLimitedException] gdy serwer odpowie 429.
  /// Wołaj bezpośrednio po każdym http.post/get w metodach auth.
  void _checkRateLimit(http.Response res) {
    if (res.statusCode != 429) return;
    int retryAfter = 60;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      retryAfter = (body['retry_after'] as num?)?.toInt() ?? retryAfter;
    } catch (_) {
      final header = res.headers['retry-after'];
      if (header != null) retryAfter = int.tryParse(header) ?? retryAfter;
    }
    throw RateLimitedException(retryAfter);
  }

  // ── Rejestracja ─────────────────────────────────────────────
  /// Rzuca [RateLimitedException] — obsłuż w UI.
  Future<({bool ok, String? error})> register({
    required String email,
    required String password,
    required String firstName,
    required String serial,
    String lastName            = '',
    String language            = 'en',
    bool   measurementsUpload  = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':                email.trim().toLowerCase(),
          'password':             password,
          'first_name':           firstName.trim(),
          'last_name':            lastName.trim(),
          'serial':               serial.trim().toUpperCase(),
          'language':             language,
          'measurements_upload':  measurementsUpload,
        }),
      ).timeout(const Duration(seconds: 15));

      _checkRateLimit(res); // rzuca RateLimitedException jeśli 429

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] == true) return (ok: true, error: null);
      return (ok: false, error: json['error'] as String? ?? 'Registration failed');
    } on RateLimitedException {
      rethrow; // niech UI samo obsłuży odliczanie
    } on Exception catch (e) {
      return (ok: false, error: 'Network error: $e');
    }
  }

  // ── Logowanie ────────────────────────────────────────────────
  /// Rzuca [RateLimitedException] — obsłuż w UI.
  Future<({bool ok, String? error})> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':       email.trim().toLowerCase(),
          'password':    password,
          'device_info': 'Flutter App',
        }),
      ).timeout(const Duration(seconds: 15));

      _checkRateLimit(res); // rzuca RateLimitedException jeśli 429

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] == true) {
        _token = json['token'] as String;
        _user  = DlUser.fromJson(json['user'] as Map<String, dynamic>);

        await _storage.write(key: _kToken, value: _token);
        await _storage.write(key: _kUser,  value: jsonEncode(_user!.toJson()));

        notifyListeners();
        await fetchLicense();
        return (ok: true, error: null);
      }
      return (ok: false, error: json['error'] as String? ?? 'Login failed');
    } on RateLimitedException {
      rethrow;
    } on Exception catch (e) {
      return (ok: false, error: 'Network error: $e');
    }
  }

  // ── Pobierz licencję ─────────────────────────────────────────
  Future<bool> fetchLicense() async {
    if (_token == null) return false;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/license/get.php'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 15));

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['ok'] == true && json['license'] != null) {
        _license = DlLicense.fromJson(json['license'] as Map<String, dynamic>);
        await _storage.write(
          key:   _kLicense,
          value: jsonEncode(_license!.toJson()),
        );
        notifyListeners();
        return true;
      }
    } on Exception catch (e) {
      debugPrint('[AuthService] fetchLicense error: $e');
    }
    return false;
  }

  // ── Wylogowanie ──────────────────────────────────────────────
  Future<void> logout() async {
    if (_token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/auth/logout.php'),
          headers: {'Authorization': 'Bearer $_token'},
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _token   = null;
    _user    = null;
    _license = null;
    await _storage.deleteAll();
    notifyListeners();
  }

  // ── Helper do zapytań API z tokenem ─────────────────────────
  Map<String, String> get authHeaders => {
    'Authorization': 'Bearer ${_token ?? ''}',
    'Content-Type':  'application/json',
  };
}