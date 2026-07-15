import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';

class GpsDiagnosticsScreen extends StatefulWidget {
  const GpsDiagnosticsScreen({super.key});

  @override
  State<GpsDiagnosticsScreen> createState() => _GpsDiagnosticsScreenState();
}

class _GpsDiagnosticsScreenState extends State<GpsDiagnosticsScreen> {
  StreamSubscription<double>? _speedSub;
  StreamSubscription<int>?    _satsSub;

  // Historia ostatnich 60 próbek prędkości
  final List<_GpsSample> _samples = [];
  static const int _maxSamples = 60;

  double _currentSpeed = 0.0;
  int    _currentSats  = 0;
  double _lastSpeed    = 0.0;
  DateTime? _lastTime;

  // Statystyki
  int    _totalSamples    = 0;
  int    _rejectedSamples = 0;
  double _maxJump         = 0.0;

  @override
  void initState() {
    super.initState();
    _lastTime = DateTime.now();

    _satsSub = btService.satellitesStream.listen((sats) {
      setState(() => _currentSats = sats);
    });

    _speedSub = btService.speedStream.listen((speed) {
      final now = DateTime.now();
      final dt  = _lastTime != null
          ? now.difference(_lastTime!).inMilliseconds / 1000.0
          : 0.1;

      _totalSamples++;

      bool rejected = false;
      String reason = '';

      // Sprawdź walidację GPS (te same progi co w dyno_screen)
      if (_lastSpeed > 0 && dt > 0) {
        final maxDelta = 60.0 * dt;
        final jump     = (speed - _lastSpeed).abs();
        if (jump > _maxJump) _maxJump = jump;

        if (jump > maxDelta) {
          rejected = true;
          reason   = 'Skok ${jump.toStringAsFixed(1)} km/h > max ${maxDelta.toStringAsFixed(1)}';
          _rejectedSamples++;
        }
      }

      setState(() {
        _currentSpeed = speed;
        _lastSpeed    = speed;
        _lastTime     = now;

        _samples.add(_GpsSample(
          speed:    speed,
          dt:       dt,
          rejected: rejected,
          reason:   reason,
          time:     now,
          sats:     _currentSats,
        ));

        if (_samples.length > _maxSamples) {
          _samples.removeAt(0);
        }
      });
    });
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    _satsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _samples.where((s) => s.rejected).length;
    final acceptRate = _totalSamples > 0
        ? ((_totalSamples - _rejectedSamples) / _totalSamples * 100)
        : 100.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Diagnostics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() {
              _samples.clear();
              _totalSamples    = 0;
              _rejectedSamples = 0;
              _maxJump         = 0.0;
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          // Panel statystyk
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatBox('Prędkość', '${_currentSpeed.toStringAsFixed(1)} km/h',
                        Colors.white),
                    _StatBox('Satelity', '$_currentSats',
                        _currentSats >= 8 ? Colors.greenAccent : Colors.orangeAccent),
                    _StatBox('Akceptacja', '${acceptRate.toStringAsFixed(0)}%',
                        acceptRate > 90 ? Colors.greenAccent : Colors.orangeAccent),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatBox('Łącznie', '$_totalSamples', Colors.grey),
                    _StatBox('Rejected', '$_rejectedSamples', Colors.redAccent),
                    _StatBox('Max skok', '${_maxJump.toStringAsFixed(1)} km/h',
                        _maxJump > 3 ? Colors.orangeAccent : Colors.greenAccent),
                  ],
                ),
              ],
            ),
          ),

          // Legenda
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                const Text('Accepted', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 16),
                Container(width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                const Text('Rejected', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Lista próbek
          Expanded(
            child: _samples.isEmpty
                ? const Center(
                    child: Text('Waiting for GPS data…',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _samples.length,
                    reverse: true, // najnowsze na górze
                    itemBuilder: (context, index) {
                      final s = _samples[_samples.length - 1 - index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: s.rejected
                              ? Colors.redAccent.withValues(alpha: 0.12)
                              : Colors.greenAccent.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: s.rejected
                                ? Colors.redAccent.withValues(alpha: 0.4)
                                : Colors.greenAccent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              s.rejected ? Icons.close : Icons.check,
                              color: s.rejected
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${s.speed.toStringAsFixed(2)} km/h',
                              style: TextStyle(
                                color: s.rejected
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'dt=${s.dt.toStringAsFixed(2)}s',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${s.sats} sat',
                              style: TextStyle(
                                color: s.sats >= 8
                                    ? Colors.grey
                                    : Colors.orangeAccent,
                                fontSize: 11,
                              ),
                            ),
                            if (s.rejected) ...[
                              const Spacer(),
                              Flexible(
                                child: Text(
                                  s.reason,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
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

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      );
}

class _GpsSample {
  final double   speed;
  final double   dt;
  final bool     rejected;
  final String   reason;
  final DateTime time;
  final int      sats;

  _GpsSample({
    required this.speed,
    required this.dt,
    required this.rejected,
    required this.reason,
    required this.time,
    required this.sats,
  });
}