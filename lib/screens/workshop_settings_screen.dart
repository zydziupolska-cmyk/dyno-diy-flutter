import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/workshop_settings.dart';
import '../main.dart';

class WorkshopSettingsScreen extends StatefulWidget {
  const WorkshopSettingsScreen({super.key});

  @override
  State<WorkshopSettingsScreen> createState() => _WorkshopSettingsScreenState();
}

class _WorkshopSettingsScreenState extends State<WorkshopSettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _customTextCtrl;
  late TextEditingController _chartMinXCtrl;
  late TextEditingController _chartMaxXCtrl;
  WorkshopSettings _settings = WorkshopSettings();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl       = TextEditingController();
    _phoneCtrl      = TextEditingController();
    _websiteCtrl    = TextEditingController();
    _customTextCtrl = TextEditingController();
    _chartMinXCtrl  = TextEditingController(text: '1000');
    _chartMaxXCtrl  = TextEditingController(text: '6000');
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await dbService.getWorkshopSettings();
    setState(() {
      _settings = s;
      _nameCtrl.text      = s.name;
      _phoneCtrl.text     = s.phone;
      _websiteCtrl.text   = s.website;
      _customTextCtrl.text= s.customText;
      _chartMinXCtrl.text = s.chartMinX.toStringAsFixed(0);
      _chartMaxXCtrl.text = s.chartMaxX.toStringAsFixed(0);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _customTextCtrl.dispose();
    _chartMinXCtrl.dispose();
    _chartMaxXCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    // Kopiuj logo do katalogu aplikacji (żeby nie zginęło)
    final appDir = await getApplicationDocumentsDirectory();
    final dest = File('${appDir.path}/workshop_logo.png');
    await File(picked.path).copy(dest.path);

    setState(() {
      _settings = _settings.copyWith(logoPath: dest.path);
    });
  }

  Future<void> _removeLogo() async {
    final logoFile = _settings.logoPath != null ? File(_settings.logoPath!) : null;
    if (logoFile != null && await logoFile.exists()) {
      await logoFile.delete();
    }
    setState(() {
      _settings = WorkshopSettings(
        id: _settings.id,
        name: _settings.name,
        phone: _settings.phone,
        website: _settings.website,
        customText: _settings.customText,
        logoPath: null,
      );
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = WorkshopSettings(
      id:         _settings.id,
      name:       _nameCtrl.text.trim(),
      phone:      _phoneCtrl.text.trim(),
      website:    _websiteCtrl.text.trim(),
      customText: _customTextCtrl.text.trim(),
      logoPath:   _settings.logoPath,
      chartMinX:  double.tryParse(_chartMinXCtrl.text) ?? 20.0,
      chartMaxX:  double.tryParse(_chartMaxXCtrl.text) ?? 200.0,
    );
    await dbService.saveWorkshopSettings(updated);
    setState(() {
      _settings = updated;
      _saving = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ustawienia warsztatu zapisane'),
        backgroundColor: Colors.greenAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasLogo = _settings.logoPath != null &&
        File(_settings.logoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia warsztatu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ZAPISZ',
                    style: TextStyle(
                        color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Te dane pojawią się na wydruku PDF w formacie do druku. '
                'Logo będzie też widoczne jako półprzezroczysty watermark na środku wykresu.',
                style: TextStyle(fontSize: 13, color: Colors.blueAccent),
              ),
            ),

            const SizedBox(height: 24),
            _sectionLabel('Dane warsztatu'),
            const SizedBox(height: 10),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nazwa warsztatu',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _websiteCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Strona www',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customTextCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Własny tekst na wydruku',
                hintText: 'np. "Pomiar GPS · NEO-M9N 10Hz"',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            const SizedBox(height: 24),
            _sectionLabel('Zakres wykresu (oś X)'),
            const SizedBox(height: 4),
            Text(
              'Zakres osi X wykresu. Przy kalibracji RPM: podaj RPM (np. 1000–6000). Bez kalibracji: km/h (np. 20–200).',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _chartMinXCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Od',
                    hintText: '1000 (RPM) / 20 (km/h)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.first_page),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _chartMaxXCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Do',
                    hintText: '6000 (RPM) / 200 (km/h)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.last_page),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 24),
            _sectionLabel('Logo warsztatu'),
            const SizedBox(height: 10),

            // Logo preview
            if (hasLogo) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_settings.logoPath!),
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Logo wgrane',
                              style: TextStyle(color: Colors.greenAccent)),
                          const SizedBox(height: 4),
                          const Text(
                            'Będzie widoczne jako watermark na wykresie i w stopce PDF',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _removeLogo,
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 16),
                            label: const Text('Usuń logo',
                                style: TextStyle(
                                    color: Colors.redAccent, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _pickLogo,
                icon: const Icon(Icons.upload_file, color: Colors.blueAccent),
                label: Text(
                  hasLogo ? 'Zmień logo' : 'Wgraj logo (PNG/JPG)',
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              'Zalecane: PNG z przezroczystym tłem, min. 300×100 px',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 30),

            // Podgląd stopki
            _sectionLabel('Podgląd stopki PDF'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (hasLogo) ...[
                    Image.file(File(_settings.logoPath!),
                        height: 36, width: 36, fit: BoxFit.contain),
                    const SizedBox(width: 10),
                  ] else ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.image_outlined,
                          size: 20, color: Colors.grey),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameCtrl.text.isEmpty
                              ? 'Nazwa warsztatu'
                              : _nameCtrl.text,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87),
                        ),
                        Text(
                          [
                            if (_phoneCtrl.text.isNotEmpty)
                              'tel. ${_phoneCtrl.text}',
                            if (_websiteCtrl.text.isNotEmpty)
                              _websiteCtrl.text,
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _customTextCtrl.text.isEmpty
                        ? 'Tekst własny'
                        : _customTextCtrl.text,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Row(
        children: [
          Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(2),
              )),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.redAccent)),
        ],
      );
}