import 'dart:math';

class PhysicsEngine {
  static const double gravity           = 9.81;
  static const double rollingResistance = 0.015;

  // ── Korekcja DIN 70020 ─────────────────────────────────────────────────────
  static double calculateDINCorrection(double tempC, double pressureHpa) {
    if (pressureHpa <= 0) return 1.0;
    return (1013.0 / pressureHpa) * sqrt((273.15 + tempC) / 293.15);
  }

  // ── Moc na kołach (pojedyncza próbka) z Masami Wirującymi ──────────────────
  static double calculateWheelHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
    double rotationalFactor = 1.05,
  }) {
    if (timeDelta <= 0 || v2KmH <= v1KmH) return 0.0;
    final vAvg   = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final a      = ((v2KmH - v1KmH) / 3.6) / timeDelta;
    final effectiveWeight = weight * rotationalFactor;
    
    return (effectiveWeight * a * vAvg) / 735.499;
  }

  // ── Straty wybiegu (pojedyncza próbka) ──────────────────────────────────────
  static double calculateCoastLossHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
  }) {
    if (timeDelta <= 0 || v1KmH <= v2KmH) return 0.0;
    final vAvg  = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final decel = ((v1KmH - v2KmH) / 3.6) / timeDelta;
    return ((weight * decel * vAvg) / 735.499).clamp(0.0, 500.0);
  }

  // ── EMA ────────────────────────────────────────────────────────────────────
  static double ema(double newVal, double prevSmoothed, double alpha) {
    if (prevSmoothed == 0.0) return newVal;
    return newVal * (1.0 - alpha) + prevSmoothed * alpha;
  }

  // ── Regresja wielomianowa (Dynomet) z Masami Wirującymi ────────────────────
  static List<List<double>> polynomialPowerCurve({
    required List<List<double>> timeSpeedPoints,
    required double weight,
    double rotationalFactor = 1.05,
    int degree = 6,
  }) {
    if (timeSpeedPoints.length < degree + 2) return [];

    final n  = timeSpeedPoints.length;
    final ts = timeSpeedPoints.map((p) => p[0]).toList();
    final vs = timeSpeedPoints.map((p) => p[1] / 3.6).toList();

    final tMin = ts.first;
    final tMax = ts.last;
    final tRange = tMax - tMin;
    if (tRange <= 0) return [];
    final tsNorm = ts.map((t) => (t - tMin) / tRange).toList();

    final A = List.generate(n, (i) {
      return List.generate(degree + 1, (j) => pow(tsNorm[i], j).toDouble());
    });

    final coeffs = _leastSquares(A, vs, degree + 1);
    if (coeffs == null) return [];

    final result = <List<double>>[];
    final effectiveWeight = weight * rotationalFactor;

    for (int i = 1; i < n - 1; i++) {
      final tN = tsNorm[i];
      final dt = tRange; 

      double vFit = 0;
      for (int j = 0; j <= degree; j++) {
        vFit += coeffs[j] * pow(tN, j);
      }

      double dv = 0;
      for (int j = 1; j <= degree; j++) {
        dv += j * coeffs[j] * pow(tN, j - 1);
      }
      final a = dv / dt; 

      if (a <= 0.1) continue; 

      final vKmh = vFit * 3.6;
      final hpW  = (effectiveWeight * a * vFit) / 735.499;

      if (hpW > 0 && vKmh > 15) {
        result.add([vKmh, hpW]);
      }
    }

    return result;
  }

  // ── Zaawansowana Regresja Kwadratowa Strat Wybiegu ─────────────────────────
  static List<double> calculateAdvancedLossRegression(
      List<List<double>> lossPoints) {
    if (lossPoints.length < 3) return [0.0, 0.0, 0.0];

    final losses = lossPoints.map((p) => p[1]).toList()..sort();
    final median = losses[losses.length ~/ 2];
    final deviations = losses.map((l) => (l - median).abs()).toList()..sort();
    final mad = deviations[deviations.length ~/ 2];
    
    final filtered = lossPoints
        .where((p) => (p[1] - median).abs() <= 3.0 * mad + 1.0)
        .toList();

    if (filtered.length < 3) {
      return [median.clamp(0.0, 100.0), 0.0, 0.0]; 
    }

    final int degree = 2;
    final int n = filtered.length;
    final vsScaled = filtered.map((p) => p[0] / 100.0).toList();
    final hpLosses = filtered.map((p) => p[1]).toList();

    final A = List.generate(n, (i) {
      return List.generate(degree + 1, (j) => pow(vsScaled[i], j).toDouble());
    });

    final coeffs = _leastSquares(A, hpLosses, degree + 1);
    
    if (coeffs == null) return [median.clamp(0.0, 100.0), 0.0, 0.0];
    return coeffs;
  }

  // ── Least squares solver (eliminacja Gaussa) ───────────────────────────────
  static List<double>? _leastSquares(
      List<List<double>> A, List<double> b, int cols) {
    final n = A.length;

    final ATA = List.generate(cols, (i) =>
        List.generate(cols, (j) {
          double sum = 0;
          for (int k = 0; k < n; k++) sum += A[k][i] * A[k][j];
          return sum;
        }));

    final ATb = List.generate(cols, (i) {
      double sum = 0;
      for (int k = 0; k < n; k++) sum += A[k][i] * b[k];
      return sum;
    });

    final aug = List.generate(cols, (i) => [...ATA[i], ATb[i]]);
    for (int col = 0; col < cols; col++) {
      int maxRow = col;
      for (int row = col + 1; row < cols; row++) {
        if (aug[row][col].abs() > aug[maxRow][col].abs()) maxRow = row;
      }
      final tmp = aug[col]; aug[col] = aug[maxRow]; aug[maxRow] = tmp;
      if (aug[col][col].abs() < 1e-12) return null;

      final pivot = aug[col][col];
      for (int j = col; j <= cols; j++) aug[col][j] /= pivot;

      for (int row = 0; row < cols; row++) {
        if (row == col) continue;
        final factor = aug[row][col];
        for (int j = col; j <= cols; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }
    return aug.map((row) => row[cols]).toList();
  }
}