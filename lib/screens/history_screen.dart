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

  // ── EKSPORT XML ───────────────────────────────────────────────────────────
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
        if (parts.length == 2) {
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
      subject: 'Dyno DIY – ${car.name} – ${runs.length} pomiar(y)',
      text: 'Eksport danych hamowni GPS\nAuto: ${car.name}\nLiczba pomiarów: ${runs.length}',
    );
  }

  // ── EKSPORT PDF ───────────────────────────────────────────────────────────
  Future<void> _exportPdf(DynoRun run) async {
    final car = _selectedCar!;
    final spots = _parseSpots(run);

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
                    pw.Text('DYNO DIY - Raport pomiaru',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Data: ${_formatDate(run.timestamp)}',
                        style: const pw.TextStyle(color: PdfColors.grey200, fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Dane pojazdu
              pw.Text('Pojazd',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              _pdfRow('Nazwa', car.name),
              if (car.licensePlate != null) _pdfRow('Rejestracja', car.licensePlate!),
              _pdfRow('Waga sesji', '${run.sessionWeightKg.toStringAsFixed(0)} kg'),
              _pdfRow('Naped', car.transmission.name.toUpperCase()),
              pw.SizedBox(height: 16),

              // Wyniki
              pw.Text('Wyniki pomiaru',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  _pdfResultBox('Moc max', '${run.maxEngineHp.toStringAsFixed(1)} KM'),
                  _pdfResultBox('Moment max', '${run.maxEngineTorque.toStringAsFixed(1)} Nm'),
                  _pdfResultBox('Korekcja DIN', '×${run.correctionFactor.toStringAsFixed(4)}'),
                ],
              ),
              pw.SizedBox(height: 16),

              // Tabela punktów
              pw.Text('Dane krzywej mocy',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _pdfCell('km/h', bold: true),
                      _pdfCell('Moc (KM)', bold: true),
                    ],
                  ),
                  ...spots.map((s) => pw.TableRow(children: [
                    _pdfCell(s.x.toStringAsFixed(1)),
                    _pdfCell(s.y.toStringAsFixed(1)),
                  ])),
                ],
              ),

              pw.Spacer(),
              pw.Divider(),
              pw.Text('Wygenerowano przez Dyno DIY App ${DateTime.now().year}',
                  style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10)),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final carName = car.name.replaceAll(' ', '_');
    final file = File('${dir.path}/dyno_${carName}_${run.timestamp.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Dyno DIY – ${car.name} – ${_formatDate(run.timestamp)}',
    );
  }


  pw.Widget _pdfRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _pdfResultBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.red900),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red900)),
            pw.SizedBox(height: 4),
            pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ],
        ),
      );

  pw.Widget _pdfCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(
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
          if (_selectedRunIds.isNotEmpty)
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
class RunDetailScreen extends StatelessWidget {
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

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  List<FlSpot> _parseSpots() {
    final spots = <FlSpot>[];
    for (final point in run.graphDataPoints) {
      final parts = point.split(';');
      if (parts.length == 2) {
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
    for (final point in run.graphDataPoints) {
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
    final spots   = _parseSpots();
    final nmSpots = _parseNmSpots();
    final maxHp = spots.isEmpty
        ? 0.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // maxNm używane do skali wykresu
    final maxVal = [maxHp, nmSpots.isEmpty ? 0.0 : nmSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b)].reduce((a,b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: Text(car.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Wydruk A4 (RPM)',
            onPressed: onExportPrintPdf,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF mobilny',
            onPressed: onExportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Eksportuj XML',
            onPressed: onExportXml,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_formatDate(run.timestamp),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            // Statystyki
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCard(
                    label: 'Moc max',
                    value: '${run.maxEngineHp.toStringAsFixed(1)} KM',
                    color: Colors.greenAccent),
                if (run.maxEngineTorque > 0)
                  _StatCard(
                      label: 'Moment max',
                      value: '${run.maxEngineTorque.toStringAsFixed(1)} Nm',
                      color: Colors.blueAccent),
                _StatCard(
                    label: 'Waga',
                    value: '${run.sessionWeightKg.toStringAsFixed(0)} kg',
                    color: Colors.orangeAccent),
                _StatCard(
                    label: 'DIN',
                    value: '×${run.correctionFactor.toStringAsFixed(3)}',
                    color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 16),
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
                          minX: 30, maxX: 200, minY: 0,
                          maxY: maxHp + 50,
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
                              axisNameWidget: const Text('km/h',
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
                          gridData:
                              const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
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

    return Container(
      padding: const EdgeInsets.only(right: 20, top: 20, bottom: 8),
      decoration: BoxDecoration(
          color: Colors.grey[950], borderRadius: BorderRadius.circular(16)),
      child: LineChart(
        LineChartData(
          minX: 30, maxX: 200, minY: 0,
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
              axisNameWidget: const Text('km/h',
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