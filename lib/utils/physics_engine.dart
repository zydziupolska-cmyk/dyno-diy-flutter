import 'dart:math';

class PhysicsEngine {
  static const double gravity           = 9.81;
  static const double airDensity        = 1.225;
  static const double rollingResistance = 0.015;

  // ── Korekcja DIN 70020 ─────────────────────────────────────────────────────
  static double calculateDINCorrection(double tempC, double pressureHpa) {
    if (pressureHpa <= 0) return 1.0;
    return (1013.0 / pressureHpa) * sqrt((273.15 + tempC) / 293.15);
  }

  // ── Moc na kołach (faza przyspieszania) ────────────────────────────────────
  //
  // METODA DYNOMET: liczymy TYLKO siłę bezwładności masy.
  // Cd i area NIE są potrzebne — opory wychodzą z fazy wybiegu.
  //
  //   P_wheel = (m × a) × v_avg
  //
  static double calculateWheelHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
  }) {
    if (timeDelta <= 0 || v2KmH <= v1KmH) return 0.0;

    final vAvg  = ((v1KmH + v2KmH) / 2.0) / 3.6;       // m/s
    final a     = ((v2KmH - v1KmH) / 3.6) / timeDelta;  // m/s²
    final powerW = weight * a * vAvg;                    // W
    return powerW / 735.499;                             // KM
  }

  // ── Straty wybiegu (faza coasting) ─────────────────────────────────────────
  //
  // Pojazd na luzie — WSZYSTKIE opory łącznie:
  //   opór powietrza + toczenie + straty napędu (łożyska, olej)
  //
  //   P_loss = (m × decel) × v_avg
  //
  static double calculateCoastLossHp({
    required double v1KmH,      // wyższa (poprzednia)
    required double v2KmH,      // niższa (aktualna)
    required double timeDelta,
    required double weight,
  }) {
    if (timeDelta <= 0 || v1KmH <= v2KmH) return 0.0;

    final vAvg   = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final decel  = ((v1KmH - v2KmH) / 3.6) / timeDelta;
    final powerW = weight * decel * vAvg;
    return (powerW / 735.499).clamp(0.0, 500.0);
  }

  // ── EMA (wygładzanie) ───────────────────────────────────────────────────────
  // alpha = 0.0 → bez wygładzania, wysoki → bardziej stary sygnał
  static double ema(double newVal, double prevSmoothed, double alpha) {
    if (prevSmoothed == 0.0) return newVal;
    return newVal * (1.0 - alpha) + prevSmoothed * alpha;
  }

  // ── Regresja liniowa strat wybiegu ─────────────────────────────────────────
  // Zwraca {a, b} gdzie: lossHp(v) = a*v + b
  static Map<String, double> calculateLossRegression(
      List<List<double>> lossPoints) {
    if (lossPoints.length < 3) return {'a': 0.0, 'b': 0.0};

    int    n     = lossPoints.length;
    double sumX  = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (final p in lossPoints) {
      sumX  += p[0];
      sumY  += p[1];
      sumXY += p[0] * p[1];
      sumX2 += p[0] * p[0];
    }

    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-10) return {'a': 0.0, 'b': (sumY / n).clamp(0.0, 100.0)};

    final a = (n * sumXY - sumX * sumY) / denom;
    final b = (sumY - a * sumX) / n;

    // Sanity: straty rosną z prędkością (a >= 0) lub są stałe
    if (a < 0) return {'a': 0.0, 'b': b.clamp(0.0, 200.0)};
    return {'a': a.clamp(0.0, 5.0), 'b': b.clamp(0.0, 200.0)};
  }
}