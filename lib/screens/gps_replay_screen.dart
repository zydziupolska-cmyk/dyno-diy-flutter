import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Import modelu z dyno_screen przez dynamic — unikamy circular import
// Przekazujemy dane jako proste listy

// Model próbki GPS - używany przez dyno_screen i gps_replay_screen
class GpsSample {
  final double speed;
  final double dt;
  final bool   rejected;
  final String reason;
  final String phase; // 'ACC' lub 'COAST'

  GpsSample({
    required this.speed,
    required this.dt,
    required this.rejected,
    required this.reason,
    required this.phase,
  });
}

class GpsReplayScreen extends StatefulWidget {
  final List<GpsSample> samples; // lista _GpsSample

  const GpsReplayScreen({super.key, required this.samples});

  @override
  State<GpsReplayScreen> createState() => _GpsReplayScreenState();
}

class _GpsReplayScreenState extends State<GpsReplayScreen> {
  String _filter = 'ALL'; // ALL, ACC, COAST, REJECTED

  List<GpsSample> get _filtered {
    switch (_filter) {
      case 'ACC':
        return widget.samples.where((s) => s.phase == 'ACC').toList();
      case 'COAST':
        return widget.samples.where((s) => s.phase == 'COAST').toList();
      case 'REJECTED':
        return widget.samples.where((s) => s.rejected).toList();
      default:
        return widget.samples;
    }
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('idx,speed_kmh,dt_ms,phase,rejected,reason');
    for (int i = 0; i < widget.samples.length; i++) {
      final s = widget.samples[i];
      buf.writeln('${i+1},${s.speed.toStringAsFixed(3)},'
          '${(s.dt*1000).toStringAsFixed(0)},'
          '${s.phase},${s.rejected ? 1 : 0},"${s.reason}"');
    }
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/gps_replay_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([XFile(file.path)],
        subject: 'GPS Replay – dane pomiarowe');
  }

  @override
  Widget build(BuildContext context) {
    final total    = widget.samples.length;
    final accepted = widget.samples.where((s) => !s.rejected).length;
    final rejected = widget.samples.where((s) => s.rejected).length;
    final accPhase = widget.samples.where((s) => s.phase == 'ACC').length;
    final coastPhase = widget.samples.where((s) => s.phase == 'COAST').length;
    final acceptRate = total > 0 ? accepted / total * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Replay'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          // Statystyki
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat('Łącznie', '$total', Colors.white),
                  _Stat('Akceptacja', '${acceptRate.toStringAsFixed(0)}%',
                      acceptRate > 90
                          ? Colors.greenAccent
                          : Colors.orangeAccent),
                  _Stat('Rejected', '$rejected', Colors.redAccent),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat('Acceleration', '$accPhase', Colors.greenAccent),
                  _Stat('Coast-down', '$coastPhase', Colors.orangeAccent),
                  _Stat('Accepted', '$accepted', Colors.greenAccent),
                ],
              ),
            ]),
          ),

          // Filtry
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final f in ['ALL', 'ACC', 'COAST', 'REJECTED'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(f,
                        style: TextStyle(
                            fontSize: 11,
                            color: _filter == f ? Colors.black : Colors.grey)),
                    selected: _filter == f,
                    selectedColor: _filterColor(f),
                    backgroundColor: Colors.grey[850],
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),

          // Legenda
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _LegendDot(Colors.greenAccent),
              const SizedBox(width: 4),
              const Text('Acceleration',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(width: 12),
              _LegendDot(Colors.orangeAccent),
              const SizedBox(width: 4),
              const Text('Coast-down',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(width: 12),
              _LegendDot(Colors.redAccent),
              const SizedBox(width: 4),
              const Text('Rejected',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 8),

          // Lista próbek
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No samples',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final s = _filtered[index];
                      final color = s.rejected
                          ? Colors.redAccent
                          : s.phase == 'ACC'
                              ? Colors.greenAccent
                              : Colors.orangeAccent;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: color.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          // Numer próbki
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 10),
                            ),
                          ),
                          // Ikona
                          Icon(
                            s.rejected ? Icons.close : Icons.check,
                            color: color,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          // Prędkość
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${s.speed.toStringAsFixed(2)} km/h',
                              style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // dt
                          SizedBox(
                            width: 55,
                            child: Text(
                              'dt:${(s.dt * 1000).toStringAsFixed(0)}ms',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 10),
                            ),
                          ),
                          // Faza
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.phase,
                              style: TextStyle(color: color, fontSize: 9),
                            ),
                          ),
                          // Powód odrzucenia
                          if (s.rejected && s.reason.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.reason,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _filterColor(String f) {
    switch (f) {
      case 'ACC':     return Colors.greenAccent;
      case 'COAST':   return Colors.orangeAccent;
      case 'REJECTED': return Colors.redAccent;
      default:        return Colors.grey;
    }
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ]);
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot(this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}