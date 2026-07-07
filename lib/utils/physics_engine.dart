import 'dart:math';

class PhysicsEngine {
  static const double gravity           = 9.81;
  static const double rollingResistance = 0.015;

  // ── Korekcja DIN 70020 ─────────────────────────────────────────────────────
  static double calculateDINCorrection(double tempC, double pressureHpa) {
    if (pressureHpa <= 0) return 1.0;
    return (1013.0 / pressureHpa) * sqrt((273.15 + tempC) / 293.15);
  }

  // ── Moc na kołach (pojedyncza próbka) ──────────────────────────────────────
  // rotationalFactor: korekcja na bezwładność wirujących mas napędu
  // (koła, wał, koło zamachowe) — typowo 1.03-1.10 zależnie od biegu.
  static double calculateWheelHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
    double rotationalFactor = 1.0,
  }) {
    if (timeDelta <= 0 || v2KmH <= v1KmH) return 0.0;
    final vAvg = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final a    = ((v2KmH - v1KmH) / 3.6) / timeDelta;
    return (weight * rotationalFactor * a * vAvg) / 735.499;
  }

  // ── Straty wybiegu (pojedyncza próbka, legacy) ─────────────────────────────
  static double calculateCoastLossHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
    double rotationalFactor = 1.0,
  }) {
    if (timeDelta <= 0 || v1KmH <= v2KmH) return 0.0;
    final vAvg  = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final decel = ((v1KmH - v2KmH) / 3.6) / timeDelta;
    return ((weight * rotationalFactor * decel * vAvg) / 735.499).clamp(0.0, 500.0);
  }

  // ── EMA ────────────────────────────────────────────────────────────────────
  static double ema(double newVal, double prevSmoothed, double alpha) {
    if (prevSmoothed == 0.0) return newVal;
    return newVal * (1.0 - alpha) + prevSmoothed * alpha;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODEL FIZYCZNY STRAT WYBIEGU
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Zamiast fitować szumne per-okno straty (V1: liniowa, V2: kwadratowa),
  // fitujemy v(t) na CAŁYM segmencie wybiegu, wyznaczamy decel(v),
  // i z tego modelujemy:
  //
  //   decel(v) = Crr·g + Kaero·v²
  //
  // co daje:
  //
  //   loss_hp(v) = m · rotFactor · decel(v) · v / 735.5
  //
  // Model ekstrapoluje POPRAWNIE do niskich prędkości (toczenie dominuje,
  // aero znika), w przeciwieństwie do clampu na zakres wybiegu.
  // ══════════════════════════════════════════════════════════════════════════

  /// Wyznacza współczynniki modelu strat [CrrG, Kaero] z surowych
  /// próbek wybiegu. coastSamples = lista [czas_s, prędkość_kmh].
  /// Zwraca [CrrG, Kaero] gotowe do użycia w coastLossAtSpeed().
  static List<double> fitCoastPhysicsModel(
      List<List<double>> coastSamples, {
      double minCrr = 0.010,
  }) {
    if (coastSamples.length < 10) {
      // Za mało danych — użyj domyślnych stałych
      return [minCrr * gravity, 0.0004];
    }

    final n  = coastSamples.length;
    final ts = coastSamples.map((p) => p[0]).toList();
    final vs = coastSamples.map((p) => p[1]).toList();

    // Fit kwadratowy: v(t) = a·t² + b·t + c
    // Normalizacja czasu dla stabilności
    final tMin = ts.first;
    final tMax = ts.last;
    final tRange = tMax - tMin;
    if (tRange <= 0) return [minCrr * gravity, 0.0004];

    final tsN = ts.map((t) => (t - tMin) / tRange).toList();

    // Macierz Vandermonde st. 2
    final A = List.generate(n, (i) =>
        [1.0, tsN[i], tsN[i] * tsN[i]]);
    final b = vs;

    final coeffs = _leastSquares(A, b, 3);
    if (coeffs == null) return [minCrr * gravity, 0.0004];

    // coeffs = [c, b_norm, a_norm] (rosnące potęgi)
    // v(tN) = coeffs[0] + coeffs[1]*tN + coeffs[2]*tN²
    // Przelicz na oryginalne t: dv/dt = (coeffs[1] + 2*coeffs[2]*tN) / tRange

    // Zbierz pary [v_ms, decel_ms2] w punktach fitu
    final decelPts = <List<double>>[];
    for (int i = 0; i < n; i++) {
      final tN = tsN[i];
      final vFit = coeffs[0] + coeffs[1] * tN + coeffs[2] * tN * tN;
      final dvdt = (coeffs[1] + 2.0 * coeffs[2] * tN) / tRange; // km/h/s
      if (dvdt < 0) {
        final vMs    = vFit / 3.6;
        final decel  = -dvdt / 3.6; // m/s²
        decelPts.add([vMs, decel]);
      }
    }

    if (decelPts.length < 5) return [minCrr * gravity, 0.0004];

    // Fit: decel = CrrG + Kaero * v²
    final Am = List.generate(decelPts.length, (i) =>
        [1.0, decelPts[i][0] * decelPts[i][0]]);
    final bm = decelPts.map((p) => p[1]).toList();

    final model = _leastSquares(Am, bm, 2);
    if (model == null) return [minCrr * gravity, 0.0004];

    // Wymuszenie fizycznych minimum:
    // - CrrG nie może być < minCrr*g (opona zawsze się toczy)
    // - Kaero nie może być < 0 (opór aero nie pomaga)
    // Przy wąskim zakresie prędkości wybiegu (np. 95-115 km/h) fit
    // nie potrafi rozdzielić Crr od aero — Crr wychodzi ~0. Dlatego
    // wymuszamy minimum z fizyki (typowa opona: Crr ≈ 0.010-0.015).
    final crrG  = model[0] < minCrr * gravity ? minCrr * gravity : model[0];
    final kaero = model[1] < 0 ? 0.0 : model[1];

    return [crrG, kaero];
  }

  /// Strata [KM] przy dowolnej prędkości — model fizyczny.
  /// coastModel = [CrrG, Kaero] z fitCoastPhysicsModel().
  static double coastLossAtSpeed(
      double speedKmh,
      List<double> coastModel,
      double weight, {
      double rotationalFactor = 1.0,
  }) {
    final vMs   = speedKmh / 3.6;
    final decel = coastModel[0] + coastModel[1] * vMs * vMs;
    return (weight * rotationalFactor * decel * vMs) / 735.499;
  }

  // ── Regresja wielomianowa na danych prędkości (metoda Dynomet) ─────────────
  // Dane wejściowe: lista [czas_s, prędkość_kmh]
  // Zwraca listę punktów [prędkość_kmh, moc_HP_koło]
  static List<List<double>> polynomialPowerCurve({
    required List<List<double>> timeSpeedPoints,
    required double weight,
    double rotationalFactor = 1.0,
    int degree = 4,
  }) {
    if (timeSpeedPoints.length < degree + 2) return [];

    final n  = timeSpeedPoints.length;
    final ts = timeSpeedPoints.map((p) => p[0]).toList();
    final vs = timeSpeedPoints.map((p) => p[1] / 3.6).toList();

    final tMin   = ts.first;
    final tMax   = ts.last;
    final tRange = tMax - tMin;
    if (tRange <= 0) return [];
    final tsNorm = ts.map((t) => (t - tMin) / tRange).toList();

    final A = List.generate(n, (i) {
      return List.generate(degree + 1, (j) => pow(tsNorm[i], j).toDouble());
    });

    final coeffs = _leastSquares(A, vs, degree + 1);
    if (coeffs == null) return [];

    // Pomijamy skrajne ~8% zakresu (efekt brzegowy wielomianu)
    final margin = (n * 0.08).round().clamp(1, n ~/ 2 - 1);
    final result = <List<double>>[];
    for (int i = margin; i < n - margin; i++) {
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
      final hpW  = (weight * rotationalFactor * a * vFit) / 735.499;

      if (hpW > 0 && vKmh > 15) {
        result.add([vKmh, hpW]);
      }
    }

    return result;
  }

  // ── Regresja liniowa strat wybiegu (legacy, do kompatybilności) ─────────────
  static Map<String, double> calculateLossRegression(
      List<List<double>> lossPoints) {
    if (lossPoints.length < 3) return {'a': 0.0, 'b': 0.0};
    final losses = lossPoints.map((p) => p[1]).toList()..sort();
    final median = losses[losses.length ~/ 2];
    final deviations = losses.map((l) => (l - median).abs()).toList()..sort();
    final mad = deviations[deviations.length ~/ 2];
    final filtered = lossPoints
        .where((p) => (p[1] - median).abs() <= 3.0 * mad + 1.0)
        .toList();
    if (filtered.length < 3) return {'a': 0.0, 'b': median.clamp(0.0, 100.0)};
    int nf = filtered.length;
    double sumX=0, sumY=0, sumXY=0, sumX2=0;
    for (final p in filtered) {
      sumX+=p[0]; sumY+=p[1]; sumXY+=p[0]*p[1]; sumX2+=p[0]*p[0];
    }
    final denom = nf * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-10) return {'a': 0.0, 'b': (sumY / nf).clamp(0.0, 100.0)};
    final a = (nf * sumXY - sumX * sumY) / denom;
    final b = (sumY - a * sumX) / nf;
    if (a < 0) return {'a': 0.0, 'b': b.clamp(0.0, 200.0)};
    return {'a': a.clamp(0.0, 5.0), 'b': b.clamp(0.0, 200.0)};
  }

  // ── Least squares solver (eliminacja Gaussa) ────────────────────────────────
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
        for (int j = col; j <= cols; j++) aug[row][j] -= factor * aug[col][j];
      }
    }
    return aug.map((row) => row[cols]).toList();
  }
}