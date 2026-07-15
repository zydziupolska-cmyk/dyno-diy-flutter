import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ota_service.dart';
import '../services/firmware_update_service.dart';
import '../main.dart';

class OtaUpdateScreen extends StatefulWidget {
  const OtaUpdateScreen({super.key});

  @override
  State<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends State<OtaUpdateScreen> {
  final OtaService            _otaService = OtaService();
  final FirmwareUpdateService _fwService  = FirmwareUpdateService();

  StreamSubscription<OtaProgress>? _progressSub;

  OtaStatus    _status     = OtaStatus.idle;
  double       _percent    = 0;
  int          _bytesSent  = 0;
  int          _bytesTotal = 0;
  String       _message    = '';
  String?      _error;
  String?      _currentVersion;
  String?      _selectedFileName;
  FirmwareInfo? _availableUpdate;
  bool         _checkingUpdate = false;

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
    _readVersionAndCheck();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _otaService.dispose();
    super.dispose();
  }

  Future<void> _readVersionAndCheck() async {
    if (!btService.isConnected) return;

    setState(() => _checkingUpdate = true);

    // Odczytaj wersję z BLE (characteristic OTA control)
    try {
      final connectedDevices = FlutterBluePlus.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        final device   = connectedDevices.first;
        final services = await device.discoverServices();
        for (final svc in services) {
          for (final char in svc.characteristics) {
            // UUID characterystyki wersji firmware z OtaService
            if (char.uuid.toString().toLowerCase().contains('ff03') ||
                char.properties.read) {
              try {
                final val = await char.read();
                if (val.isNotEmpty) {
                  final ver = String.fromCharCodes(val).trim();
                  if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(ver)) {
                    if (mounted) setState(() => _currentVersion = ver);
                    break;
                  }
                }
              } catch (_) {}
            }
          }
          if (_currentVersion != null) break;
        }
      }
    } catch (_) {}

    // Sprawdź czy jest nowsza wersja na serwerze
    final update = await _fwService.checkForUpdate(_currentVersion ?? '0.0.0');
    if (mounted) {
      setState(() {
        _availableUpdate  = update;
        _checkingUpdate   = false;
      });
    }
  }

  // ── Pobierz z serwera i wgraj ────────────────────────────────
  Future<void> _downloadAndInstall() async {
    if (_availableUpdate == null) return;
    setState(() { _error = null; _selectedFileName = null; });

    if (!btService.isConnected) {
      setState(() => _error = 'ESP32 not connected');
      return;
    }

    final connectedDevices = FlutterBluePlus.connectedDevices;
    if (connectedDevices.isEmpty) {
      setState(() => _error = 'No BLE device found');
      return;
    }

    // Pokaż postęp pobierania
    setState(() {
      _status  = OtaStatus.connecting;
      _message = 'Downloading firmware v${_availableUpdate!.version}…';
    });

    final bytes = await _fwService.downloadFirmware(_availableUpdate!.url);
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _status = OtaStatus.error;
        _error  = 'Failed to download firmware. Check your connection.';
      });
      return;
    }

    setState(() => _selectedFileName = 'dynomic_${_availableUpdate!.version}.bin');
    await _sendOta(connectedDevices.first, Uint8List.fromList(bytes));
  }

  // ── Wybierz plik ręcznie ─────────────────────────────────────
  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      setState(() => _error = 'Cannot read file');
      return;
    }
    if (file.size < 1000) {
      setState(() => _error = 'File too small — does not look like firmware');
      return;
    }
    if (file.size > 1900000) {
      setState(() => _error = 'File too large (max 1.9 MB for OTA partition)');
      return;
    }

    // Sprawdź magic bytes ESP32 (0xE9)
    if (file.bytes![0] != 0xE9) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Warning',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'This file does not appear to be ESP32 firmware '
            '(missing 0xE9 header). Continue anyway?',
            style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue',
                  style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!btService.isConnected) {
      setState(() => _error = 'ESP32 not connected');
      return;
    }

    final connectedDevices = FlutterBluePlus.connectedDevices;
    if (connectedDevices.isEmpty) {
      setState(() => _error = 'No BLE device found');
      return;
    }

    setState(() {
      _selectedFileName = file.name;
      _error = null;
    });

    await _sendOta(connectedDevices.first, Uint8List.fromList(file.bytes!));
  }

  Future<void> _sendOta(dynamic device, Uint8List bytes) async {
    await _otaService.uploadFirmware(device, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final isIdle    = _status == OtaStatus.idle || _status == OtaStatus.error;
    final isSuccess = _status == OtaStatus.success;
    final isWorking = _status == OtaStatus.uploading ||
                      _status == OtaStatus.connecting ||
                      _status == OtaStatus.verifying;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware update',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Status połączenia ────────────────────────────────
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
                  btService.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: btService.isConnected
                      ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      btService.isConnected
                          ? 'ESP32 connected'
                          : 'ESP32 not connected',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: btService.isConnected
                            ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    if (_currentVersion != null)
                      Text('Current firmware: v$_currentVersion',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    if (_checkingUpdate)
                      const Text('Checking for updates…',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                )),
                if (_checkingUpdate)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.grey)),
              ]),
            ),

            const SizedBox(height: 16),

            // ── Dostępna aktualizacja z serwera ─────────────────
            if (_availableUpdate != null && isIdle) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.system_update,
                          color: Colors.greenAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Update available: v${_availableUpdate!.version}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent),
                      ),
                    ]),
                    if (_availableUpdate!.changelog.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _availableUpdate!.changelog,
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: btService.isConnected
                            ? _downloadAndInstall
                            : null,
                        icon: const Icon(Icons.download, size: 20),
                        label: Text(
                          'Download & install  '
                          '(${(_availableUpdate!.size / 1024).toStringAsFixed(0)} KB)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Aktualna wersja OK ───────────────────────────────
            if (_availableUpdate == null &&
                !_checkingUpdate &&
                _currentVersion != null &&
                isIdle) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  Text('Firmware is up to date (v$_currentVersion)',
                      style: const TextStyle(
                          color: Colors.blueAccent, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Instrukcja ręczna (zwijana) ──────────────────────
           /* ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Manual update from file',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              children: [
                const SizedBox(height: 8),
                _step('1', 'Compile firmware in Arduino IDE '
                    '(Sketch → Export Compiled Binary)'),
                _step('2', 'Copy .bin file to your phone'),
                _step('3', 'Tap "Choose .bin file" below'),
                _step('4', 'ESP32 restarts automatically after upload'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orangeAccent, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Arduino IDE: Tools → Partition Scheme → '
                      '"Minimal SPIFFS (1.9MB APP with OTA)"',
                      style: TextStyle(
                          color: Colors.orangeAccent, fontSize: 11),
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: (isIdle && btService.isConnected)
                        ? _pickAndUpload
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blueAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.file_upload,
                        color: Colors.blueAccent),
                    label: const Text('Choose .bin file',
                        style: TextStyle(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),*/

            const SizedBox(height: 8),

            // ── Progress ─────────────────────────────────────────
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

            // ── Błąd ─────────────────────────────────────────────
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
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13)),
              ),
            ],

            if (_selectedFileName != null && isIdle) ...[
              const SizedBox(height: 8),
              Text('File: $_selectedFileName',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12)),
            ],

            const Spacer(),
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
                    color: Colors.blueAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: const TextStyle(
                  color: Colors.grey, fontSize: 13))),
        ],
      ),
    );
  }
}