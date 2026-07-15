import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pokazuje się tylko przy pierwszym uruchomieniu aplikacji.
/// Zapamiętuje że był pokazany przez SharedPreferences.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _ctrl = PageController();
  int _page = 0;

  static const _pages = [
    _Page(
      icon: Icons.satellite_alt,
      color: Color(0xFF22c55e),
      title: 'Mount the GPS module',
      subtitle: 'Place the magnetic antenna on your car roof '
          'for a clear view of the sky. Connect the module '
          'to power via USB.',
      steps: [
        'Put the magnetic antenna on the roof',
        'Connect the module to a 5 V USB source (power bank or car charger)',
        'Wait for the green LED — GPS is acquiring satellites',
      ],
    ),
    _Page(
      icon: Icons.tune,
      color: Color(0xFF3b82f6),
      title: 'Calibrate K-Factor',
      subtitle: 'One-time calibration links your GPS speed '
          'to engine RPM. You only need to do this once per vehicle.',
      steps: [
        'Pair the module via Bluetooth in the app',
        'Drive in 3rd or 4th gear and hold exactly 3 000 RPM',
        'Tap "Save calibration" when speed stabilises',
      ],
    ),
    _Page(
      icon: Icons.speed,
      color: Color(0xFFE51C1C),
      title: 'Run a dyno measurement',
      subtitle: 'Find a safe, straight, flat road. '
          'Accelerate hard through the RPM range and lift off '
          'when the graph flattens.',
      steps: [
        'Select your vehicle in the garage',
        'Tap START RUN and accelerate flat out',
        'Lift off — the app captures the coast-down curve automatically',
        'Your HP and Nm curve appears instantly',
      ],
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ),

            // Slajdy
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(page: _pages[i]),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width:  _page == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _page == i
                      ? _pages[_page].color
                      : Colors.grey[700],
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),

            const SizedBox(height: 24),

            // Przycisk
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pages[_page].color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    _page < _pages.length - 1
                        ? 'Next'
                        : 'Get started',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Page {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;
  final List<String> steps;
  const _Page({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.steps,
  });
}

class _SlideView extends StatelessWidget {
  final _Page page;
  const _SlideView({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ikona w kole
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.color.withValues(alpha: 0.12),
              border: Border.all(
                  color: page.color.withValues(alpha: 0.3), width: 2),
            ),
            child: Icon(page.icon, size: 56, color: page.color),
          ),

          const SizedBox(height: 36),

          Text(page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2)),

          const SizedBox(height: 12),

          Text(page.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[400],
                  height: 1.55)),

          const SizedBox(height: 28),

          // Kroki
          ...page.steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24, height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: page.color.withValues(alpha: 0.15),
                  ),
                  child: Text('${e.key + 1}',
                      style: TextStyle(
                          color: page.color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.value,
                      style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 14,
                          height: 1.45)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}