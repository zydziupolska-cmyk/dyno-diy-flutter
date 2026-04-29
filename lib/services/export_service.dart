import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/car_profile.dart';
import '../models/workshop_settings.dart';

class ExportService {

  // ══════════════════════════════════════════════════════════════
  //  PDF – FORMAT DO DRUKU (poziomy A4, oś X = RPM)
  // ══════════════════════════════════════════════════════════════
  Future<void> exportPrintPdf({
    required DynoRun run,
    required CarProfile car,
    required WorkshopSettings workshop,
    required double kFactor,
    double? tempC,
    double? pressureHpa,
  }) async {
    // Parsuj punkty → RPM
    final hpPts = <_Pt>[];
    final nmPts = <_Pt>[];
    for (final p in run.graphDataPoints) {
      final parts = p.split(';');
      if (parts.length < 2) continue;
      final speed = double.tryParse(parts[0]);
      final hp    = double.tryParse(parts[1]);
      if (speed == null || hp == null) continue;
      final rpm = speed * kFactor;
      hpPts.add(_Pt(rpm, hp));
      if (rpm > 0) nmPts.add(_Pt(rpm, (hp * 9550.0) / rpm));
    }
    hpPts.sort((a, b) => a.x.compareTo(b.x));
    nmPts.sort((a, b) => a.x.compareTo(b.x));

    double maxHp = 0, maxHpRpm = 0, maxNm = 0, maxNmRpm = 0;
    for (final p in hpPts) { if (p.y > maxHp) { maxHp = p.y; maxHpRpm = p.x; } }
    for (final p in nmPts) { if (p.y > maxNm) { maxNm = p.y; maxNmRpm = p.x; } }

    final totalRatio = kFactor * (2.0 * pi * 0.318) / 60.0;
    final minRpm     = hpPts.isNotEmpty ? hpPts.first.x : 1000.0;
    final maxRpm     = hpPts.isNotEmpty ? hpPts.last.x  : 6000.0;
    final maxHpAxis  = ((maxHp / 30).ceil() * 30.0) + 30;
    final maxNmAxis  = ((maxNm / 60).ceil() * 60.0) + 60;

    pw.MemoryImage? logoImg;
    if (workshop.logoPath != null) {
      final f = File(workshop.logoPath!);
      if (await f.exists()) logoImg = pw.MemoryImage(await f.readAsBytes());
    }

    final pdf = pw.Document();
    final font = pw.Font.courier();

    // Generuj SVG wykresu jako string
    final chartSvg = _buildChartSvg(
      hpPts: hpPts, nmPts: nmPts,
      minRpm: minRpm, maxRpm: maxRpm,
      maxHpAxis: maxHpAxis, maxNmAxis: maxNmAxis,
      maxHp: maxHp, maxHpRpm: maxHpRpm,
      maxNm: maxNm, maxNmRpm: maxNmRpm,
      workshopName: workshop.name,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // ── Nagłówek ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(car.name,
                      style: pw.TextStyle(font: font, fontSize: 13,
                          fontWeight: pw.FontWeight.bold)),
                  if (car.licensePlate != null)
                    pw.Text(car.licensePlate!,
                        style: pw.TextStyle(font: font, fontSize: 9,
                            color: PdfColors.grey600)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Air press   ${pressureHpa?.toStringAsFixed(0) ?? "—"} hPa\n'
                    'Air temp    ${tempC?.toStringAsFixed(1) ?? "—"} °C',
                    style: pw.TextStyle(font: font, fontSize: 8,
                        color: PdfColors.grey700),
                  ),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Total ratio   ${totalRatio.toStringAsFixed(3)}',
                      style: pw.TextStyle(font: font, fontSize: 8,
                          color: PdfColors.grey700)),
                  pw.Text('DIN 70020',
                      style: pw.TextStyle(font: font, fontSize: 8,
                          color: PdfColors.grey700)),
                  pw.Text(_fmtDate(run.timestamp),
                      style: pw.TextStyle(font: font, fontSize: 8,
                          color: PdfColors.grey700)),
                ]),
              ],
            ),

            pw.SizedBox(height: 3),

            // ── Peak legenda ──
            pw.Row(children: [
              pw.Text(
                '${maxHp.toStringAsFixed(1)} Hp / ${maxHpRpm.toStringAsFixed(0)} Rpm',
                style: pw.TextStyle(font: font, fontSize: 9,
                    fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
              pw.SizedBox(width: 20),
              pw.Text(
                '${maxNm.toStringAsFixed(1)} Nm / ${maxNmRpm.toStringAsFixed(0)} Rpm',
                style: pw.TextStyle(font: font, fontSize: 9,
                    fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            ]),

            pw.SizedBox(height: 4),

            // ── Wykres jako SVG ──
            pw.Expanded(
              child: pw.SvgImage(svg: chartSvg),
            ),

            pw.SizedBox(height: 4),

            // ── Stopka ──
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
              ),
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(children: [
                    if (logoImg != null) ...[
                      pw.Image(logoImg, height: 22, width: 22,
                          fit: pw.BoxFit.contain),
                      pw.SizedBox(width: 6),
                    ],
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (workshop.name.isNotEmpty)
                            pw.Text(workshop.name,
                                style: pw.TextStyle(font: font, fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          pw.Text(
                            [
                              if (workshop.phone.isNotEmpty)
                                'tel. ${workshop.phone}',
                              if (workshop.website.isNotEmpty)
                                workshop.website,
                            ].join('  ·  '),
                            style: pw.TextStyle(font: font, fontSize: 8,
                                color: PdfColors.grey600),
                          ),
                        ]),
                  ]),
                  pw.Text(
                    workshop.customText.isNotEmpty
                        ? workshop.customText
                        : 'Pomiar GPS · Dyno DIY App',
                    style: pw.TextStyle(font: font, fontSize: 8,
                        color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final dir  = await getTemporaryDirectory();
    final name = car.name.replaceAll(' ', '_');
    final file = File(
        '${dir.path}/dyno_print_${name}_${run.timestamp.millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)],
        subject: 'Dyno DIY – ${car.name} – wydruk');
  }

  // ── Generuj wykres jako SVG string ───────────────────────────────────────
  String _buildChartSvg({
    required List<_Pt> hpPts,
    required List<_Pt> nmPts,
    required double minRpm, required double maxRpm,
    required double maxHpAxis, required double maxNmAxis,
    required double maxHp, required double maxHpRpm,
    required double maxNm, required double maxNmRpm,
    required String workshopName,
  }) {
    const W = 800.0, H = 300.0;
    const lm = 40.0, rm = 40.0, tm = 8.0, bm = 22.0;
    final cw = W - lm - rm;
    final ch = H - tm - bm;

    double toX(double rpm) => lm + (rpm - minRpm) / (maxRpm - minRpm) * cw;
    double toYhp(double hp) => tm + ch - (hp / maxHpAxis) * ch;
    double toYnm(double nm) => tm + ch - (nm / maxNmAxis) * ch;

    final buf = StringBuffer();
    buf.write('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 $W $H" width="$W" height="$H">');

    // Tło
    buf.write('<rect x="$lm" y="$tm" width="$cw" height="$ch" '
        'fill="white" stroke="#aaa" stroke-width="0.8"/>');

    // Grid pionowe
    final rpmRange = maxRpm - minRpm;
    final rpmStep  = _niceStep(rpmRange / 6);
    for (double rpm = _roundUp(minRpm, rpmStep); rpm <= maxRpm; rpm += rpmStep) {
      final x = toX(rpm);
      buf.write('<line x1="${x.toStringAsFixed(1)}" y1="$tm" '
          'x2="${x.toStringAsFixed(1)}" y2="${(tm+ch).toStringAsFixed(1)}" '
          'stroke="#ddd" stroke-width="0.4"/>');
      buf.write('<text x="${x.toStringAsFixed(1)}" '
          'y="${(H-4).toStringAsFixed(1)}" '
          'text-anchor="middle" font-size="8" fill="#555" font-family="Courier">'
          '${rpm.toStringAsFixed(0)}</text>');
    }

    // Grid poziome + etykiety
    final hpStep = _niceStep(maxHpAxis / 5);
    for (double hp = 0; hp <= maxHpAxis; hp += hpStep) {
      final y = toYhp(hp);
      buf.write('<line x1="$lm" y1="${y.toStringAsFixed(1)}" '
          'x2="${(lm+cw).toStringAsFixed(1)}" y2="${y.toStringAsFixed(1)}" '
          'stroke="#ddd" stroke-width="0.4"/>');
      // Hp (lewa)
      buf.write('<text x="${(lm-3).toStringAsFixed(1)}" '
          'y="${(y+3).toStringAsFixed(1)}" '
          'text-anchor="end" font-size="8" fill="#c0392b" font-family="Courier">'
          '${hp.toStringAsFixed(0)}</text>');
      // Nm (prawa)
      final nm = hp / maxHpAxis * maxNmAxis;
      buf.write('<text x="${(lm+cw+3).toStringAsFixed(1)}" '
          'y="${(y+3).toStringAsFixed(1)}" '
          'font-size="8" fill="#27ae60" font-family="Courier">'
          '${nm.toStringAsFixed(0)}</text>');
    }

    // Etykieta osi X
    buf.write('<text x="${(lm+cw/2).toStringAsFixed(1)}" '
        'y="${(H-2).toStringAsFixed(1)}" '
        'text-anchor="middle" font-size="8" fill="#666" font-family="Courier">'
        'RPM</text>');

    // Watermark
    final wm = workshopName.isNotEmpty
        ? workshopName.toUpperCase() : 'DYNO DIY';
    buf.write('<text x="${(lm+cw/2).toStringAsFixed(1)}" '
        'y="${(tm+ch/2+10).toStringAsFixed(1)}" '
        'text-anchor="middle" font-size="28" fill="#ccc" '
        'fill-opacity="0.35" font-family="Courier" font-weight="bold">'
        '$wm</text>');

    // ── Krzywa Nm (zielona) — pod HP ──
    if (nmPts.length > 1) {
      final polyNm = nmPts.map((p) =>
          '${toX(p.x).toStringAsFixed(1)},${toYnm(p.y).toStringAsFixed(1)}').join(' ');
      final fillNm =
          '${toX(nmPts.first.x).toStringAsFixed(1)},${(tm+ch).toStringAsFixed(1)} '
          '$polyNm '
          '${toX(nmPts.last.x).toStringAsFixed(1)},${(tm+ch).toStringAsFixed(1)}';
      buf.write('<polygon points="$fillNm" fill="#27ae60" fill-opacity="0.08"/>');
      buf.write('<polyline points="$polyNm" fill="none" '
          'stroke="#27ae60" stroke-width="1.8" '
          'stroke-linejoin="round" stroke-linecap="round"/>');
    }

    // ── Krzywa HP (czerwona) — na wierzchu ──
    if (hpPts.length > 1) {
      final polyHp = hpPts.map((p) =>
          '${toX(p.x).toStringAsFixed(1)},${toYhp(p.y).toStringAsFixed(1)}').join(' ');
      final fillHp =
          '${toX(hpPts.first.x).toStringAsFixed(1)},${(tm+ch).toStringAsFixed(1)} '
          '$polyHp '
          '${toX(hpPts.last.x).toStringAsFixed(1)},${(tm+ch).toStringAsFixed(1)}';
      buf.write('<polygon points="$fillHp" fill="#c0392b" fill-opacity="0.08"/>');
      buf.write('<polyline points="$polyHp" fill="none" '
          'stroke="#c0392b" stroke-width="2" '
          'stroke-linejoin="round" stroke-linecap="round"/>');
    }

    // Marker peak HP
    if (maxHpRpm > 0) {
      final x = toX(maxHpRpm); final y = toYhp(maxHp);
      buf.write('<line x1="${x.toStringAsFixed(1)}" y1="$tm" '
          'x2="${x.toStringAsFixed(1)}" y2="${(tm+ch).toStringAsFixed(1)}" '
          'stroke="#c0392b" stroke-width="0.6" stroke-dasharray="4,3"/>');
      buf.write('<circle cx="${x.toStringAsFixed(1)}" cy="${y.toStringAsFixed(1)}" '
          'r="3.5" fill="#c0392b"/>');
    }

    // Marker peak Nm
    if (maxNmRpm > 0) {
      final x = toX(maxNmRpm); final y = toYnm(maxNm);
      buf.write('<line x1="${x.toStringAsFixed(1)}" y1="$tm" '
          'x2="${x.toStringAsFixed(1)}" y2="${(tm+ch).toStringAsFixed(1)}" '
          'stroke="#27ae60" stroke-width="0.6" stroke-dasharray="4,3"/>');
      buf.write('<circle cx="${x.toStringAsFixed(1)}" cy="${y.toStringAsFixed(1)}" '
          'r="3.5" fill="#27ae60"/>');
    }

    // Ramka
    buf.write('<rect x="$lm" y="$tm" width="$cw" height="$ch" '
        'fill="none" stroke="#888" stroke-width="0.8"/>');

    buf.write('</svg>');
    return buf.toString();
  }

  // ══════════════════════════════════════════════════════════════
  //  XML – EKSPORT
  // ══════════════════════════════════════════════════════════════
  Future<void> exportXml({
    required List<DynoRun> runs,
    required CarProfile car,
    double? kFactor,
  }) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<DynoDIY version="1.0" exportDate="${DateTime.now().toIso8601String()}">');
    buf.writeln('  <Vehicle>');
    buf.writeln('    <Name>${_e(car.name)}</Name>');
    buf.writeln('    <LicensePlate>${_e(car.licensePlate ?? "")}</LicensePlate>');
    buf.writeln('    <WeightKg>${car.weightKg}</WeightKg>');
    buf.writeln('    <Cd>${car.cd}</Cd>');
    buf.writeln('    <FrontalArea>${car.area}</FrontalArea>');
    buf.writeln('    <DrivetrainLoss>${car.lossDrivetrain}</DrivetrainLoss>');
    buf.writeln('    <Transmission>${car.transmission.name}</Transmission>');
    if (kFactor != null) {
      buf.writeln('    <KFactor>${kFactor.toStringAsFixed(6)}</KFactor>');
    }
    buf.writeln('  </Vehicle>');
    buf.writeln('  <Runs count="${runs.length}">');
    for (final run in runs) {
      buf.writeln('    <Run id="${run.id}">');
      buf.writeln('      <Timestamp>${run.timestamp.toIso8601String()}</Timestamp>');
      buf.writeln('      <MaxEngineHp>${run.maxEngineHp.toStringAsFixed(2)}</MaxEngineHp>');
      buf.writeln('      <MaxEngineTorqueNm>${run.maxEngineTorque.toStringAsFixed(2)}</MaxEngineTorqueNm>');
      buf.writeln('      <SessionWeightKg>${run.sessionWeightKg.toStringAsFixed(1)}</SessionWeightKg>');
      buf.writeln('      <CorrectionFactorDIN>${run.correctionFactor.toStringAsFixed(6)}</CorrectionFactorDIN>');
      buf.writeln('      <DataPoints count="${run.graphDataPoints.length}">');
      for (final pt in run.graphDataPoints) {
        final parts = pt.split(';');
        if (parts.length == 2) {
          final speed = double.tryParse(parts[0]);
          final hp    = double.tryParse(parts[1]);
          if (speed != null && hp != null) {
            final rpm = kFactor != null ? speed * kFactor : null;
            final nm  = (rpm != null && rpm > 0) ? (hp * 9550.0) / rpm : null;
            buf.write('        <Point speedKmh="${parts[0]}" hp="${parts[1]}"');
            if (rpm != null) buf.write(' rpm="${rpm.toStringAsFixed(0)}"');
            if (nm  != null) buf.write(' nm="${nm.toStringAsFixed(1)}"');
            buf.writeln('/>');
          }
        }
      }
      buf.writeln('      </DataPoints>');
      buf.writeln('    </Run>');
    }
    buf.writeln('  </Runs>');
    buf.writeln('</DynoDIY>');

    final dir  = await getTemporaryDirectory();
    final name = car.name.replaceAll(' ', '_');
    final file = File(
        '${dir.path}/dyno_${name}_${DateTime.now().millisecondsSinceEpoch}.xml');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([XFile(file.path)],
        subject: 'Dyno DIY – ${car.name} – ${runs.length} pomiar(y)');
  }

  // ══════════════════════════════════════════════════════════════
  //  XML – IMPORT
  // ══════════════════════════════════════════════════════════════
  Future<ImportResult> importXml(String xmlContent) async {
    try {
      final carName  = _tag(xmlContent, 'Name') ?? 'Importowany pojazd';
      final carPlate = _tag(xmlContent, 'LicensePlate');
      final weightKg = double.tryParse(_tag(xmlContent, 'WeightKg') ?? '') ?? 1400;
      final cd       = double.tryParse(_tag(xmlContent, 'Cd') ?? '') ?? 0.30;
      final area     = double.tryParse(_tag(xmlContent, 'FrontalArea') ?? '') ?? 2.2;
      final loss     = double.tryParse(_tag(xmlContent, 'DrivetrainLoss') ?? '') ?? 0.15;
      final kFactor  = double.tryParse(_tag(xmlContent, 'KFactor') ?? '');

      final runs = <ImportedRun>[];
      for (final m in RegExp(r'<Run[^>]*>(.*?)</Run>',
          dotAll: true).allMatches(xmlContent)) {
        final rx = m.group(1) ?? '';
        final points = <String>[];
        for (final pm in RegExp(r'<Point ([^/]+)/>').allMatches(rx)) {
          final attrs = pm.group(1) ?? '';
          final speed = _attr(attrs, 'speedKmh');
          final hp    = _attr(attrs, 'hp');
          if (speed != null && hp != null) points.add('$speed;$hp');
        }
        runs.add(ImportedRun(
          timestamp: DateTime.tryParse(_tag(rx, 'Timestamp') ?? '') ?? DateTime.now(),
          maxEngineHp:      double.tryParse(_tag(rx, 'MaxEngineHp') ?? '') ?? 0,
          maxEngineTorque:  double.tryParse(_tag(rx, 'MaxEngineTorqueNm') ?? '') ?? 0,
          sessionWeightKg:  double.tryParse(_tag(rx, 'SessionWeightKg') ?? '') ?? weightKg,
          correctionFactor: double.tryParse(_tag(rx, 'CorrectionFactorDIN') ?? '') ?? 1.0,
          graphDataPoints:  points,
        ));
      }

      return ImportResult(
        carName: carName, licensePlate: carPlate,
        weightKg: weightKg, cd: cd, area: area,
        lossDrivetrain: loss, kFactor: kFactor, runs: runs,
      );
    } catch (e) {
      throw Exception('Błąd parsowania XML: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double _niceStep(double raw) {
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    final n = raw / magnitude;
    if (n < 1.5) return magnitude;
    if (n < 3.5) return 2 * magnitude;
    if (n < 7.5) return 5 * magnitude;
    return 10 * magnitude;
  }

  double _roundUp(double value, double step) => (value / step).ceil() * step;

  String? _tag(String xml, String tag) =>
      RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml)?.group(1)?.trim();

  String? _attr(String attrs, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);

  String _e(String s) => s
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'
      '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _Pt { final double x, y; _Pt(this.x, this.y); }

class ImportResult {
  final String carName;
  final String? licensePlate;
  final double weightKg, cd, area, lossDrivetrain;
  final double? kFactor;
  final List<ImportedRun> runs;
  ImportResult({required this.carName, this.licensePlate,
    required this.weightKg, required this.cd, required this.area,
    required this.lossDrivetrain, this.kFactor, required this.runs});
}

class ImportedRun {
  final DateTime timestamp;
  final double maxEngineHp, maxEngineTorque, sessionWeightKg, correctionFactor;
  final List<String> graphDataPoints;
  ImportedRun({required this.timestamp, required this.maxEngineHp,
    required this.maxEngineTorque, required this.sessionWeightKg,
    required this.correctionFactor, required this.graphDataPoints});
}