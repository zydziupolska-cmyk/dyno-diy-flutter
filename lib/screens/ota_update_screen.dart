import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ota_service.dart';
import '../main.dart';

/// Ekran aktualizacji firmware ESP32 przez BLE.
/// Dostępny z menu/ustawień — użytkownik wybiera plik .bin,
/// aplikacja wysyła go do ESP32, ESP32 restartuje się automatycznie.
class OtaUpdateScreen extends StatefulWidget {
  const OtaUpdateScreen({super.key});

  @override
  State<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends State<OtaUpdateScreen> {
  final OtaService _otaService = OtaService();
  StreamSubscription<OtaProgress>? _progressSub;

  OtaStatus _status = OtaStatus.idle;
  double  _percent   = 0;
  int     _bytesSent = 0;
  int     _bytesTotal = 0;
  String  _message   = '';
  String? _error;
  String? _currentVersion;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    _progressSub = _otaService.progressStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _status     = p.status;
        _percent    = p.percent;
        _bytesSent  = p.bytesSent;
        _bytesTotal = p.bytesTotal;
        _message    = p.message ?? '';
        _error      = p.error;
      });
    });
    _readVersion();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _otaService.dispose();
    super.dispose();
  }

  Future<void> _readVersion() async {
    if (btService.isConnected) {
      // Potrzebujemy dostępu do urządzenia BLE
      // btService._device jest prywatny, więc odczytujemy wersję
      // przez OTA control characteristic przy następnym połączeniu
      setState(() => _currentVersion = '(połącz się, żeby sprawdzić)');
    }
  }

  Future<void> _pickAndUpload() async {
    // ── Wybierz plik .bin ──
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      setState(() => _error = 'Nie można odczytać pliku');
      return;
    }

    // Weryfikacja podstawowa
    if (file.size < 1000) {
      setState(() => _error = 'Plik za mały — to nie wygląda na firmware');
      return;
    }
    if (file.size > 1900000) {
      setState(() => _error = 'Plik za duży (max 1.9 MB dla partycji OTA)');
      return;
    }

    // Sprawdź magic bytes ESP32 firmware (0xE9 na początku)
    if (file.bytes![0] != 0xE9) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uwaga'),
          content: const Text(
            'Ten plik nie wygląda na firmware ESP32 '
            '(brak nagłówka 0xE9). Czy na pewno chcesz kontynuować?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anuluj')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kontynuuj')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _selectedFileName = file.name;
      _error = null;
    });

    if (!btService.isConnected) {
      setState(() => _error = 'ESP32 nie jest połączony!');
      return;
    }

    // Potrzebujemy BluetoothDevice — pobierz z FlutterBluePlus
    final connectedDevices = FlutterBluePlus.connectedDevices;
    final dynoDevice = connectedDevices.where((d) =>
        d.platformName.contains('Dyno') || d.platformName.contains('ESP32'));

    if (dynoDevice.isEmpty) {
      setState(() => _error = 'Nie znaleziono urządzenia DynoESP');
      return;
    }

    await _otaService.uploadFirmware(
      dynoDevice.first,
      Uint8List.fromList(file.bytes!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIdle = _status == OtaStatus.idle || _status == OtaStatus.error;
    final isSuccess = _status == OtaStatus.success;
    final isWorking = _status == OtaStatus.uploading ||
        _status == OtaStatus.connecting ||
        _status == OtaStatus.verifying;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktualizacja firmware',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status połączenia ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: btService.isConnected
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: btService.isConnected
                      ? Colors.greenAccent : Colors.redAccent),
              ),
              child: Row(children: [
                Icon(
                  btService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: btService.isConnected ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      btService.isConnected ? 'ESP32 połączony' : 'ESP32 niepołączony',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: btService.isConnected ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    if (_currentVersion != null)
                      Text('Firmware: $_currentVersion',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                )),
              ]),
            ),

            const SizedBox(height: 24),

            // ── Instrukcja ──
            const Text('Jak zaktualizować:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _step('1', 'Skompiluj firmware w Arduino IDE (Sketch → Export Compiled Binary)'),
            _step('2', 'Skopiuj plik .bin na telefon'),
            _step('3', 'Naciśnij "Wybierz plik .bin" poniżej'),
            _step('4', 'ESP32 zrestartuje się automatycznie po wgraniu'),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber, color: Colors.orangeAccent, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'W Arduino IDE ustaw: Tools → Partition Scheme → '
                  '"Minimal SPIFFS (1.9MB APP with OTA)"',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                )),
              ]),
            ),

            const SizedBox(height: 24),

            // ── Progress ──
            if (isWorking || isSuccess) ...[
              Text(_message,
                  style: TextStyle(
                    color: isSuccess ? Colors.greenAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _percent > 0 ? _percent : null,
                  minHeight: 10,
                  backgroundColor: Colors.grey[800],
                  color: isSuccess ? Colors.greenAccent : Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(_bytesSent / 1024).toStringAsFixed(0)} / '
                '${(_bytesTotal / 1024).toStringAsFixed(0)} KB',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],

            // ── Błąd ──
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            ],

            if (_selectedFileName != null && isIdle) ...[
              const SizedBox(height: 8),
              Text('Plik: $_selectedFileName',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],

            const Spacer(),

            // ── Przycisk ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (isIdle && btService.isConnected) ? _pickAndUpload : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  disabledBackgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(
                  isWorking ? Icons.hourglass_top
                      : isSuccess ? Icons.check_circle
                      : Icons.file_upload,
                  color: Colors.white,
                ),
                label: Text(
                  isWorking ? 'Wgrywanie...'
                      : isSuccess ? 'Gotowe! ESP32 restartuje się'
                      : 'Wybierz plik .bin i wgraj',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blueAccent.withValues(alpha: 0.2),
            ),
            child: Text(num,
                style: const TextStyle(
                    color: Colors.blueAccent, fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: const TextStyle(color: Colors.grey, fontSize: 13))),
        ],
      ),
    );
  }
}