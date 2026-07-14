import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/car_profile.dart';
import '../services/export_service.dart';
import '../services/measurement_upload_service.dart';
import '../main.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<CarProfile> _cars = [];
  CarProfile? _selectedCar;
  List<DynoRun> _runs = [];
  List<int> _selectedRunIds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCars();
  }

  Future<void> _loadCars() async {
    final cars = await dbService.getAllCars();
    setState(() {
      _cars = cars;
      _selectedCar = cars.isNotEmpty ? cars.first : null;
    });
    if (_selectedCar != null) await _loadRuns();
  }

  Future<void> _loadRuns() async {
    if (_selectedCar == null) return;
    setState(() => _loading = true);
    final runs = await dbService.getRunsForCar(_selectedCar!.id);
    setState(() {
      _runs = runs;
      _selectedRunIds.clear();
      _loading = false;
    });
  }

  Future<void> _deleteRun(DynoRun run) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Usuń pomiar?'),
        content: Text('Pomiar z ${_formatDate(run.timestamp)} zostanie trwale usunięty.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await dbService.db.delete('runs', where: 'id = ?', whereArgs: [run.id]);
      await _loadRuns();
    }
  }

  // ── UPLOAD DO CHMURY ─────────────────────────────────────────
  Future<void> _uploadSelected() async {
    if (_selectedRunIds.isEmpty) return;

    final selected = _runs
        .where((r) => _selectedRunIds.contains(r.id))
        .toList();

    if (!authService.isLoggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zaloguj się aby wysyłać pomiary do chmury')),
        );
      }
      return;
    }

    if (authService.user?.measurementsUpload != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Włącz cloud sync w ustawieniach aplikacji'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Pokaż progress
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wysyłam ${selected.length} pomiarów...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final svc = MeasurementUploadService(authService);
    int ok = 0;
    for (final run in selected) {
      final success = await svc.upload(
        maxHp:      run.maxEngineHp,
        maxNm:      run.maxEngineTorque,
        weightKg:   run.sessionWeightKg,
        correction: run.correctionFactor,
        measuredAt: run.timestamp,
      );
      if (success) {
        await dbService.markRunSynced(run.id);
        ok++;
      }
    }

    if (mounted) {
      setState(() => _selectedRunIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('☁️ Zsynchronizowano $ok/${selected.length} pomiarów'),
          backgroundColor: ok == selected.length ? Colors.blue : Colors.orange,
        ),
      );
    }
  }
  Future<void> _exportXml(List<DynoRun> runs) async {
    if (runs.isEmpty) return;
    final car = _selectedCar!;

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<DynoDIY version="1.0" exportDate="${DateTime.now().toIso8601String()}">');
    buffer.writeln('  <Vehicle>');
    buffer.writeln('    <Name>${car.name}</Name>');
    buffer.writeln('    <LicensePlate>${car.licensePlate ?? ""}</LicensePlate>');
    buffer.writeln('    <WeightKg>${car.weightKg}</WeightKg>');
    buffer.writeln('    <Cd>${car.cd}</Cd>');
    buffer.writeln('    <Area>${car.area}</Area>');
    buffer.writeln('    <Transmission>${car.transmission.name}</Transmission>');
    buffer.writeln('  </Vehicle>');
    buffer.writeln('  <Runs count="${runs.length}">');

    for (final run in runs) {
      buffer.writeln('    <Run id="${run.id}">');
      buffer.writeln('      <Timestamp>${run.timestamp.toIso8601String()}</Timestamp>');
      buffer.writeln('      <MaxEngineHp>${run.maxEngineHp.toStringAsFixed(2)}</MaxEngineHp>');
      buffer.writeln('      <MaxEngineTorqueNm>${run.maxEngineTorque.toStringAsFixed(2)}</MaxEngineTorqueNm>');
      buffer.writeln('      <SessionWeightKg>${run.sessionWeightKg.toStringAsFixed(1)}</SessionWeightKg>');
      buffer.writeln('      <CorrectionFactorDIN>${run.correctionFactor.toStringAsFixed(6)}</CorrectionFactorDIN>');
      buffer.writeln('      <DataPoints count="${run.graphDataPoints.length}">');
      for (final point in run.graphDataPoints) {
        final parts = point.split(';');
        if (parts.length >= 2) {
          buffer.writeln('        <Point speedKmh="${parts[0]}" hp="${parts[1]}"/>');
        }
      }
      buffer.writeln('      </DataPoints>');
      buffer.writeln('    </Run>');
    }

    buffer.writeln('  </Runs>');
    buffer.writeln('</DynoDIY>');

    final dir = await getTemporaryDirectory();
    final carName = car.name.replaceAll(' ', '_');
    final file = File('${dir.path}/dyno_${carName}_${DateTime.now().millisecondsSinceEpoch}.xml');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Dynomic – ${car.name} – ${runs.length} pomiar(y)',
      text: 'Eksport danych hamowni GPS\nAuto: ${car.name}\nLiczba pomiarów: ${runs.length}',
    );
  }

  // ── EKSPORT PDF ───────────────────────────────────────────────────────────
  Future<void> _exportPdf(DynoRun run) async {
    final car      = _selectedCar!;
    final spots    = _parseSpots(run);
    final workshop = await dbService.getWorkshopSettings();

    // Zamień polskie znaki na ASCII (pdf/courier nie obsługuje UTF-8)
    String ascii(String s) => s
        .replaceAll('ą','a').replaceAll('ć','c').replaceAll('ę','e')
        .replaceAll('ł','l').replaceAll('ń','n').replaceAll('ó','o')
        .replaceAll('ś','s').replaceAll('ź','z').replaceAll('ż','z')
        .replaceAll('Ą','A').replaceAll('Ć','C').replaceAll('Ę','E')
        .replaceAll('Ł','L').replaceAll('Ń','N').replaceAll('Ó','O')
        .replaceAll('Ś','S').replaceAll('Ź','Z').replaceAll('Ż','Z');

    final font = pw.Font.courier();

    pw.MemoryImage? logoImg;
    if (workshop.logoPath != null) {
      final f = File(workshop.logoPath!);
      if (await f.exists()) logoImg = pw.MemoryImage(await f.readAsBytes());
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Nagłówek
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red900,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DYNOMIC - Raport pomiaru',
                        style: pw.TextStyle(
                            font: font, color: PdfColors.white,
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Data: ${_formatDate(run.timestamp)}',
                        style: pw.TextStyle(font: font,
                            color: PdfColors.grey200, fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Dane pojazdu
              pw.Text('Pojazd',
                  style: pw.TextStyle(font: font, fontSize: 14,
                      fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              _pdfRow(ascii('Nazwa'), ascii(car.name), font: font),
              if (car.licensePlate != null)
                _pdfRow('Rejestracja', ascii(car.licensePlate!), font: font),
              _pdfRow('Waga sesji',
                  '${run.sessionWeightKg.toStringAsFixed(0)} kg', font: font),
              _pdfRow('Naped', ascii(car.transmission.name.toUpperCase()),
                  font: font),
              pw.SizedBox(height: 16),

              // Wyniki
              pw.Text('Wyniki pomiaru',
                  style: pw.TextStyle(font: font, fontSize: 14,
                      fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  _pdfResultBox('Moc max',
                      '${run.maxEngineHp.toStringAsFixed(1)} KM', font: font),
                  _pdfResultBox('Moment max',
                      '${run.maxEngineTorque.toStringAsFixed(1)} Nm', font: font),
                  _pdfResultBox('Korekcja DIN',
                      'x${run.correctionFactor.toStringAsFixed(4)}', font: font),
                ],
              ),
              pw.SizedBox(height: 16),

              // Tabela punktów
              pw.Text('Dane krzywej mocy',
                  style: pw.TextStyle(font: font, fontSize: 14,
                      fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              if (spots.isEmpty)
                pw.Text('Brak danych', style: pw.TextStyle(font: font,
                    color: PdfColors.grey, fontSize: 10))
              else
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _pdfCell('km/h', bold: true, font: font),
                        _pdfCell('Moc (KM)', bold: true, font: font),
                        _pdfCell('Moment (Nm)', bold: true, font: font),
                      ],
                    ),
                    // Co 3. punkt żeby tabela nie była gigantyczna
                    ...List.generate(
                      ((spots.length + 2) ~/ 3),
                      (i) {
                        final s = spots[i * 3];
                        // Pobierz Nm z danych
                        String nm = '-';
                        if (i * 3 < run.graphDataPoints.length) {
                          final parts = run.graphDataPoints[i * 3].split(';');
                          if (parts.length >= 3) nm = double.tryParse(parts[2])?.toStringAsFixed(1) ?? '-';
                        }
                        return pw.TableRow(children: [
                          _pdfCell(s.x.toStringAsFixed(1), font: font),
                          _pdfCell(s.y.toStringAsFixed(1), font: font),
                          _pdfCell(nm, font: font),
                        ]);
                      },
                    ),
                  ],
                ),

              pw.Spacer(),
              pw.Divider(),
              // Stopka warsztatu
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(children: [
                    if (logoImg != null) ...[
                      pw.Image(logoImg, height: 20, width: 20,
                          fit: pw.BoxFit.contain),
                      pw.SizedBox(width: 6),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (workshop.name.isNotEmpty)
                          pw.Text(ascii(workshop.name),
                              style: pw.TextStyle(font: font, fontSize: 9,
                                  fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                          [
                            if (workshop.phone.isNotEmpty)
                              'tel. ${workshop.phone}',
                            if (workshop.website.isNotEmpty)
                              workshop.website,
                          ].join('  .  '),
                          style: pw.TextStyle(font: font, fontSize: 8,
                              color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ]),
                  pw.Text(
                    'Dynomic App ${DateTime.now().year}',
                    style: pw.TextStyle(font: font, fontSize: 8,
                        color: PdfColors.grey),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final dir     = await getTemporaryDirectory();
    final carName = car.name.replaceAll(' ', '_');
    final file    = File(
        '${dir.path}/dyno_${carName}_${run.timestamp.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Dynomic – ${car.name} – ${_formatDate(run.timestamp)}',
    );
  }


  pw.Widget _pdfRow(String label, String value, {pw.Font? font}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: font, color: PdfColors.grey700)),
            pw.Text(value, style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _pdfResultBox(String label, String value, {pw.Font? font}) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.red900),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    font: font, fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red900)),
            pw.SizedBox(height: 4),
            pw.Text(label, style: pw.TextStyle(font: font,
                fontSize: 10, color: PdfColors.grey)),
          ],
        ),
      );

  pw.Widget _pdfCell(String text, {bool bold = false, pw.Font? font}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(
                font: font,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontSize: 10)),
      );

  // ── HELPERS ───────────────────────────────────────────────────────────────
  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  List<FlSpot> _parseSpots(DynoRun run) {
    final spots = <FlSpot>[];
    for (final point in run.graphDataPoints) {
      final parts = point.split(';');
      if (parts.length >= 2) {
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x != null && y != null) spots.add(FlSpot(x, y));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  void _openComparison() {
    final selected = _runs.where((r) => _selectedRunIds.contains(r.id)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComparisonScreen(runs: selected)),
    );
  }

  Future<void> _importXml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final content = await file.readAsString();

    try {
      final exportSvc = ExportService();
      final imported = await exportSvc.importXml(content);

      if (!mounted) return;

      // Pokaż dialog z podsumowaniem
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Importuj dane XML'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auto: ${imported.carName}'),
              Text('Liczba pomiarów: ${imported.runs.length}'),
              if (imported.kFactor != null)
                Text('K-Factor: ${imported.kFactor!.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              const Text(
                'Czy dodać to auto i pomiary do bazy danych?',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importuj',
                  style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Zapisz auto do bazy
      final car = CarProfile(
        name: imported.carName,
        licensePlate: imported.licensePlate,
        weightKg: imported.weightKg,
        cd: imported.cd,
        area: imported.area,
        lossDrivetrain: imported.lossDrivetrain,
        transmission: TransmissionType.manual,
      );
      final carId = await dbService.saveCar(car);

      // Zapisz k-factor jeśli jest
      if (imported.kFactor != null) {
        final speedAt3000 = 3000.0 / imported.kFactor!;
        await dbService.saveCalibration(carId, speedAt3000);
      }

      // Zapisz pomiary
      for (final run in imported.runs) {
        await dbService.saveRun(DynoRun(
          carId: carId,
          timestamp: run.timestamp,
          maxEngineHp: run.maxEngineHp,
          maxEngineTorque: run.maxEngineTorque,
          sessionWeightKg: run.sessionWeightKg,
          correctionFactor: run.correctionFactor,
          graphDataPoints: run.graphDataPoints,
        ));
      }

      await _loadCars();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Zaimportowano: ${imported.carName} · ${imported.runs.length} pomiarów'),
          backgroundColor: Colors.greenAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd importu: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _exportPrintPdf(DynoRun run) async {
    if (_selectedCar == null) return;
    final cal = await dbService.getLatestCalibration(_selectedCar!.id);
    if (cal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brak kalibracji – nie można obliczyć RPM dla wydruku'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    final workshop = await dbService.getWorkshopSettings();
    final exportSvc = ExportService();
    await exportSvc.exportPrintPdf(
      run: run,
      car: _selectedCar!,
      workshop: workshop,
      kFactor: cal['kFactor']!,
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selectedRuns = _runs.where((r) => _selectedRunIds.contains(r.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archiwum Pomiarów'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Importuj XML',
            onPressed: _importXml,
          ),
          if (_selectedRunIds.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Wyślij zaznaczone do chmury',
              onPressed: _uploadSelected,
            ),
            IconButton(
              icon: const Icon(Icons.code),
              tooltip: 'Eksportuj XML',
              onPressed: () {
                final selected = _runs
                    .where((r) => _selectedRunIds.contains(r.id))
                    .toList();
                final exportSvc = ExportService();
                exportSvc.exportXml(runs: selected, car: _selectedCar!);
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Wybór pojazdu
          if (_cars.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<CarProfile>(
                value: _selectedCar,
                decoration: const InputDecoration(
                  labelText: 'Pojazd',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
                items: _cars
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) {
                  setState(() => _selectedCar = c);
                  _loadRuns();
                },
              ),
            ),

          // Przycisk porównania + eksport XML zaznaczonych
          if (_selectedRunIds.length >= 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.stacked_line_chart, color: Colors.white),
                      label: Text(
                        'PORÓWNAJ ${_selectedRunIds.length}',
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                      onPressed: _openComparison,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.code, color: Colors.white),
                    label: const Text('XML', style: TextStyle(color: Colors.white)),
                    onPressed: () => _exportXml(selectedRuns),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.redAccent))
                : _runs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.show_chart, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                              _selectedCar == null
                                  ? 'Brak pojazdów w garażu'
                                  : 'Brak pomiarów dla ${_selectedCar!.name}',
                              style:
                                  const TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _runs.length,
                        itemBuilder: (context, index) {
                          final run = _runs[index];
                          final isSelected = _selectedRunIds.contains(run.id);
                          final colors = [
                            Colors.greenAccent,
                            Colors.blueAccent,
                            Colors.orangeAccent,
                            Colors.purpleAccent,
                          ];
                          final color = colors[index % colors.length];

                          return Dismissible(
                            key: Key('run_${run.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete, color: Colors.redAccent),
                            ),
                            confirmDismiss: (_) async {
                              await _deleteRun(run);
                              return false;
                            },
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: isSelected ? Colors.grey[850] : Colors.grey[900],
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  color: isSelected ? color : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RunDetailScreen(
                                      run: run,
                                      car: _selectedCar!,
                                      onExportPdf: () => _exportPdf(run),
                                      onExportPrintPdf: () => _exportPrintPdf(run),
                                      onExportXml: () {
                                        final exportSvc = ExportService();
                                        exportSvc.exportXml(
                                          runs: [run],
                                          car: _selectedCar!,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            color.withValues(alpha: 0.15),
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _formatDate(run.timestamp),
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  '${run.maxEngineHp.toStringAsFixed(1)} KM',
                                                  style: TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: color,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (run.maxEngineTorque > 0)
                                                  Text(
                                                    '${run.maxEngineTorque.toStringAsFixed(0)} Nm',
                                                    style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.blueAccent),
                                                  ),
                                              ],
                                            ),
                                            Text(
                                              'Waga: ${run.sessionWeightKg.toStringAsFixed(0)} kg',
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: color,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedRunIds.add(run.id);
                                            } else {
                                              _selectedRunIds.remove(run.id);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  SZCZEGÓŁY POMIARU
// ============================================================
class RunDetailScreen extends StatefulWidget {
  final DynoRun run;
  final CarProfile car;
  final VoidCallback onExportPdf;
  final VoidCallback onExportPrintPdf;
  final VoidCallback onExportXml;

  const RunDetailScreen({
    super.key,
    required this.run,
    required this.car,
    required this.onExportPdf,
    required this.onExportPrintPdf,
    required this.onExportXml,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  double _smoothing = 0.0; // 0 = brak filtra, 1 = max

  // Zastosuj EMA do listy punktów
  List<FlSpot> _applySmoothing(List<FlSpot> raw) {
    if (_smoothing < 0.05 || raw.length < 2) return raw;
    final result = <FlSpot>[];
    double prev = raw.first.y;
    for (final spot in raw) {
      final smoothed = spot.y * (1 - _smoothing) + prev * _smoothing;
      prev = smoothed;
      result.add(FlSpot(spot.x, smoothed));
    }
    return result;
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  List<FlSpot> _parseSpots() {
    final spots = <FlSpot>[];
    for (final point in widget.run.graphDataPoints) {
      final parts = point.split(';');
      if (parts.length >= 2) {
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x != null && y != null) spots.add(FlSpot(x, y));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  List<FlSpot> _parseNmSpots() {
    final spots = <FlSpot>[];
    for (final point in widget.run.graphDataPoints) {
      final parts = point.split(';');
      if (parts.length >= 3) {
        final x  = double.tryParse(parts[0]);
        final nm = double.tryParse(parts[2]);
        if (x != null && nm != null && nm > 0) spots.add(FlSpot(x, nm));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final spots   = _applySmoothing(_parseSpots());
    final nmSpots = _applySmoothing(_parseNmSpots());
    final maxHp = spots.isEmpty ? 0.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final maxNm = nmSpots.isEmpty ? 0.0
        : nmSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    // Zakres osi X z danych — od min do max prędkości
    final minX = spots.isEmpty ? 0.0
        : (spots.map((s) => s.x).reduce((a, b) => a < b ? a : b) - 3.0)
            .clamp(0.0, double.infinity);
    final maxX = spots.isEmpty ? 200.0
        : (spots.map((s) => s.x).reduce((a, b) => a > b ? a : b) + 5.0);

    // Dynamiczne maxY — zaokrąglone w górę do najbliższych 50
    // KM i Nm na tej samej osi — bierzemy max z obu
    final maxVal = [maxHp, maxNm].reduce((a, b) => a > b ? a : b);
    final maxY   = (maxVal * 1.25 / 50).ceil() * 50.0;
    // Minimalne maxY = 2× peak żeby peak był w środku wykresu
    final maxYFinal = maxY < maxHp * 1.8 ? (maxHp * 2 / 50).ceil() * 50.0 : maxY;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.car.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Wydruk A4 (RPM)',
            onPressed: widget.onExportPrintPdf,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF mobilny',
            onPressed: widget.onExportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Eksportuj XML',
            onPressed: widget.onExportXml,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_formatDate(widget.run.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            // Statystyki
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard(
                    label: 'Moc max',
                    value: '${maxHp.toStringAsFixed(1)} KM',
                    color: Colors.greenAccent),
                if (maxNm > 0)
                  _StatCard(
                      label: 'Moment max',
                      value: '${maxNm.toStringAsFixed(1)} Nm',
                      color: Colors.blueAccent),
                _StatCard(
                    label: 'Waga',
                    value: '${widget.run.sessionWeightKg.toStringAsFixed(0)} kg',
                    color: Colors.orangeAccent),
                _StatCard(
                    label: 'DIN',
                    value: '×${widget.run.correctionFactor.toStringAsFixed(3)}',
                    color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 8),
            // Suwak wygładzania
            Row(children: [
              const Icon(Icons.tune, color: Colors.grey, size: 16),
              const SizedBox(width: 6),
              const Text('Filtr:', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _smoothing,
                  min: 0.0, max: 0.9, divisions: 9,
                  activeColor: Colors.greenAccent,
                  inactiveColor: Colors.grey,
                  label: _smoothing == 0 ? 'RAW' : '${(_smoothing * 100).toStringAsFixed(0)}%',
                  onChanged: (v) => setState(() => _smoothing = v),
                ),
              ),
              SizedBox(width: 40,
                child: Text(
                  _smoothing == 0 ? 'RAW' : '${(_smoothing * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: _smoothing == 0 ? Colors.orangeAccent : Colors.greenAccent,
                    fontSize: 11, fontWeight: FontWeight.bold),
                )),
            ]),
            const SizedBox(height: 4),
            // Wykres
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(right: 20, top: 20),
                decoration: BoxDecoration(
                    color: Colors.grey[950],
                    borderRadius: BorderRadius.circular(16)),
                child: spots.isEmpty
                    ? const Center(
                        child: Text('Brak danych wykresu',
                            style: TextStyle(color: Colors.grey)))
                    : LineChart(
                        LineChartData(
                          minX: minX,
                          maxX: maxX,
                          minY: 0,
                          maxY: maxYFinal,
                          lineBarsData: [
                            // Nm (niebieska, pod HP)
                            if (nmSpots.isNotEmpty)
                              LineChartBarData(
                                spots: nmSpots,
                                isCurved: true,
                                curveSmoothness: 0.3,
                                color: Colors.blueAccent,
                                barWidth: 3,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.blueAccent.withValues(alpha: 0.04)),
                              ),
                            // HP (zielona, na wierzchu)
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              curveSmoothness: 0.3,
                              color: Colors.greenAccent,
                              barWidth: 4,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.greenAccent
                                      .withValues(alpha: 0.05)),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              axisNameWidget: const Text('KM',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (v, m) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 10)),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              axisNameWidget: const Text('RPM',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (v, m) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 10)),
                              ),
                            ),
                          ),
                          gridData: const FlGridData(
                              show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                          // Linie peak — pionowe przerywane na max KM i max Nm
                          extraLinesData: ExtraLinesData(
                            verticalLines: [
                              if (spots.isNotEmpty) VerticalLine(
                                x: spots.reduce((a,b) => a.y>b.y?a:b).x,
                                color: Colors.greenAccent.withValues(alpha: 0.5),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                                label: VerticalLineLabel(
                                  show: true,
                                  alignment: Alignment.topRight,
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  labelResolver: (_) =>
                                    '${maxHp.toStringAsFixed(1)} KM',
                                ),
                              ),
                              if (nmSpots.isNotEmpty) VerticalLine(
                                x: nmSpots.reduce((a,b) => a.y>b.y?a:b).x,
                                color: Colors.blueAccent.withValues(alpha: 0.5),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                                label: VerticalLineLabel(
                                  show: true,
                                  alignment: Alignment.topLeft,
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  labelResolver: (_) =>
                                    '${maxNm.toStringAsFixed(1)} Nm',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }
}

// ============================================================
//  PORÓWNANIE WYKRESÓW
// ============================================================
class ComparisonScreen extends StatefulWidget {
  final List<DynoRun> runs;
  const ComparisonScreen({super.key, required this.runs});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Kolory dla każdego pomiaru
  static const _colors = [
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.cyanAccent,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<FlSpot> _parseHpSpots(DynoRun run) {
    final spots = <FlSpot>[];
    for (final pt in run.graphDataPoints) {
      final p = pt.split(';');
      if (p.length >= 2) {
        final x = double.tryParse(p[0]);
        final y = double.tryParse(p[1]);
        if (x != null && y != null) spots.add(FlSpot(x, y));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  List<FlSpot> _parseNmSpots(DynoRun run) {
    final spots = <FlSpot>[];
    for (final pt in run.graphDataPoints) {
      final p = pt.split(';');
      if (p.length >= 3) {
        final x  = double.tryParse(p[0]);
        final nm = double.tryParse(p[2]);
        if (x != null && nm != null && nm > 0) spots.add(FlSpot(x, nm));
      }
    }
    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  Widget _buildChart({
    required List<List<FlSpot>> allSpots,
    required String yLabel,
    required Color axisColor,
  }) {
    double maxY = 0;
    final bars = <LineChartBarData>[];

    for (int i = 0; i < allSpots.length; i++) {
      final spots = allSpots[i];
      if (spots.isNotEmpty) {
        final m = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        if (m > maxY) maxY = m;
      }
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: _colors[i % _colors.length],
        barWidth: 3,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: _colors[i % _colors.length].withValues(alpha: 0.04),
        ),
      ));
    }

    if (maxY == 0) {
      return const Center(
        child: Text('Brak danych do porównania',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final allX = allSpots.expand((s) => s).map((s) => s.x).toList();
    final minX = allX.isEmpty ? 1000.0 : (allX.reduce((a,b) => a<b?a:b) - 100).clamp(0.0, double.infinity);
    final maxX = allX.isEmpty ? 6000.0 : allX.reduce((a,b) => a>b?a:b) + 200;

    return Container(
      padding: const EdgeInsets.only(right: 20, top: 20, bottom: 8),
      decoration: BoxDecoration(
          color: Colors.grey[950], borderRadius: BorderRadius.circular(16)),
      child: LineChart(
        LineChartData(
          minX: minX, maxX: maxX, minY: 0,
          maxY: maxY + maxY * 0.1,
          lineBarsData: bars,
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: Text(yLabel,
                  style: TextStyle(color: axisColor, fontSize: 11)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('RPM',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, m) => Text(v.toInt().toString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            ),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hpData = widget.runs.map(_parseHpSpots).toList();
    final nmData = widget.runs.map(_parseNmSpots).toList();
    final hasNm  = nmData.any((s) => s.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Porównanie'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Moc (KM)'),
            Tab(text: 'Moment (Nm)'),
          ],
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.grey,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Legenda
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: List.generate(widget.runs.length, (i) {
                final run = widget.runs[i];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 20, height: 3,
                        color: _colors[i % _colors.length]),
                    const SizedBox(width: 5),
                    Text(
                      '${_fmtDate(run.timestamp)}  '
                      '${run.maxEngineHp.toStringAsFixed(0)} KM'
                      '${run.maxEngineTorque > 0 ? " / ${run.maxEngineTorque.toStringAsFixed(0)} Nm" : ""}',
                      style: TextStyle(
                          color: _colors[i % _colors.length], fontSize: 11),
                    ),
                  ],
                );
              }),
            ),
            const SizedBox(height: 12),
            // Wykresy na zakładkach
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Zakładka KM
                  _buildChart(
                    allSpots: hpData,
                    yLabel: 'KM',
                    axisColor: Colors.greenAccent,
                  ),
                  // Zakładka Nm
                  hasNm
                      ? _buildChart(
                          allSpots: nmData,
                          yLabel: 'Nm',
                          axisColor: Colors.blueAccent,
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.grey, size: 48),
                              SizedBox(height: 12),
                              Text(
                                'Brak danych Nm.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                'Wykonaj nowy pomiar z kalibracja.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}