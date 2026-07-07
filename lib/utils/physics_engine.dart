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
  // (koła, wał, koło zamachowe) — realnie przyspiesza się nie tylko masa
  // pojazdu, ale i te elementy. Typowo 1.03-1.10 zależnie od biegu/przełożenia.
  static double calculateWheelHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
    double rotationalFactor = 1.0,
  }) {
    if (timeDelta <= 0 || v2KmH <= v1KmH) return 0.0;
    final vAvg   = ((v1KmH + v2KmH) / 2.0) / 3.6;
    final a      = ((v2KmH - v1KmH) / 3.6) / timeDelta;
    return (weight * rotationalFactor * a * vAvg) / 735.499;
  }

  // ── Straty wybiegu ──────────────────────────────────────────────────────────
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

  // ── Regresja wielomianowa na danych prędkości (metoda Dynomet) ─────────────
  // Dane wejściowe: lista [czas_s, prędkość_kmh]
  // Zwraca listę punktów [prędkość_kmh, moc_HP_koło]
  static List<List<double>> polynomialPowerCurve({
    required List<List<double>> timeSpeedPoints, // [[t, v_kmh], ...]
    required double weight,
    double rotationalFactor = 1.0,
    // Stopień 6 na małej próbce (~200 pkt) daje efekt Rungego blisko brzegów
    // okna — obserwowane jako fałszywy peak Nm tuż po starcie przyspieszania.
    // Stopień 3-4 wystarcza do opisania krzywej mocy silnika spalinowego
    // i jest dużo stabilniejszy na brzegach.
    int degree = 4,
  }) {
    if (timeSpeedPoints.length < degree + 2) return [];

    final n   = timeSpeedPoints.length;
    final ts  = timeSpeedPoints.map((p) => p[0]).toList();
    final vs  = timeSpeedPoints.map((p) => p[1] / 3.6).toList(); // m/s

    // Normalizacja czasu do [0, 1]
    final tMin = ts.first;
    final tMax = ts.last;
    final tRange = tMax - tMin;
    if (tRange <= 0) return [];
    final tsNorm = ts.map((t) => (t - tMin) / tRange).toList();

    // Macierz Vandermonde
    final A = List.generate(n, (i) {
      return List.generate(degree + 1, (j) => pow(tsNorm[i], j).toDouble());
    });

    // Least squares: A^T * A * x = A^T * v
    final coeffs = _leastSquares(A, vs, degree + 1);
    if (coeffs == null) return [];

    // Oblicz moc w punktach pomiaru.
    // Pomijamy skrajne ~8% zakresu z każdej strony: nawet niski stopień
    // wielomianu ma podwyższoną wariancję pochodnej blisko brzegów domeny
    // dopasowania (klasyczny efekt brzegowy przy regresji wielomianowej).
    // Wcześniejszy peak 383 Nm siedział dokładnie w tej strefie.
    final margin = (n * 0.08).round().clamp(1, n ~/ 2 - 1);
    final result = <List<double>>[];
    for (int i = margin; i < n - margin; i++) {
      final tN   = tsNorm[i];
      final dt   = tRange; // bo tsNorm jest unormowany

      // Prędkość z wielomianu
      double vFit = 0;
      for (int j = 0; j <= degree; j++) {
        vFit += coeffs[j] * pow(tN, j);
      }

      // Pochodna (przyspieszenie) - przez różniczkowanie wielomianu
      double dv = 0;
      for (int j = 1; j <= degree; j++) {
        dv += j * coeffs[j] * pow(tN, j - 1);
      }
      final a = dv / dt; // [m/s²] - dzielimy przez tRange bo normalizacja

      if (a <= 0.1) continue; // nie liczymy gdy nie przyspiesza

      final vKmh  = vFit * 3.6;
      final hpW   = (weight * rotationalFactor * a * vFit) / 735.499;

      if (hpW > 0 && vKmh > 15) {
        result.add([vKmh, hpW]);
      }
    }

    return result;
  }

  // ── Regresja liniowa strat wybiegu ─────────────────────────────────────────
  static Map<String, double> calculateLossRegression(
      List<List<double>> lossPoints) {
    if (lossPoints.length < 3) return {'a': 0.0, 'b': 0.0};

    // MAD outlier rejection
    final losses = lossPoints.map((p) => p[1]).toList()..sort();
    final median = losses[losses.length ~/ 2];
    final deviations = losses.map((l) => (l - median).abs()).toList()..sort();
    final mad = deviations[deviations.length ~/ 2];
    final filtered = lossPoints
        .where((p) => (p[1] - median).abs() <= 3.0 * mad + 1.0)
        .toList();

    if (filtered.length < 3) return {'a': 0.0, 'b': median.clamp(0.0, 100.0)};

    int    nf    = filtered.length;
    double sumX  = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in filtered) {
      sumX  += p[0]; sumY  += p[1];
      sumXY += p[0] * p[1]; sumX2 += p[0] * p[0];
    }
    final denom = nf * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-10) {
      return {'a': 0.0, 'b': (sumY / nf).clamp(0.0, 100.0)};
    }
    final a = (nf * sumXY - sumX * sumY) / denom;
    final b = (sumY - a * sumX) / nf;
    if (a < 0) return {'a': 0.0, 'b': b.clamp(0.0, 200.0)};
    return {'a': a.clamp(0.0, 5.0), 'b': b.clamp(0.0, 200.0)};
  }

  // ── Regresja kwadratowa strat wybiegu ──────────────────────────────────────
  // Fizycznie lepszy model niż liniowy: opór aerodynamiczny rośnie z v²,
  // opór toczenia jest w przybliżeniu stały -> loss(v) = c0 + c1*vScale + c2*vScale²,
  // gdzie vScale = speed_kmh / 100 (dla numerycznej stabilności współczynników).
  // Zwraca [c0, c1, c2]. Ta sama odporność na odstające wartości (MAD) co
  // calculateLossRegression powyżej.
  static List<double> calculateAdvancedLossRegression(
      List<List<double>> lossPoints) {
    if (lossPoints.isEmpty) return [0.0, 0.0, 0.0];

    final losses = lossPoints.map((p) => p[1]).toList()..sort();
    final median = losses[losses.length ~/ 2];

    if (lossPoints.length < 4) {
      return [median.clamp(0.0, 100.0), 0.0, 0.0];
    }

    final deviations = losses.map((l) => (l - median).abs()).toList()..sort();
    final mad = deviations[deviations.length ~/ 2];
    final filtered = lossPoints
        .where((p) => (p[1] - median).abs() <= 3.0 * mad + 1.0)
        .toList();

    if (filtered.length < 4) {
      return [median.clamp(0.0, 100.0), 0.0, 0.0];
    }

    final n = filtered.length;
    final A = List.generate(n, (i) {
      final vScale = filtered[i][0] / 100.0;
      return [1.0, vScale, vScale * vScale];
    });
    final b = filtered.map((p) => p[1]).toList();

    final coeffs = _leastSquares(A, b, 3);
    if (coeffs == null) {
      return [median.clamp(0.0, 100.0), 0.0, 0.0];
    }

    // Sanity clamps — bez tego ekstrapolacja poza zakres pomiaru
    // (np. do niskich prędkości na starcie krzywej mocy) mogłaby dać
    // absurdalne albo ujemne straty.
    final c0 = coeffs[0].clamp(0.0, 100.0);
    final c1 = coeffs[1].clamp(-50.0, 100.0);
    final c2 = coeffs[2].clamp(-50.0, 100.0);
    return [c0, c1, c2];
  }

  // ── Least squares solver (eliminacja Gaussa) ────────────────────────────────
  static List<double>? _leastSquares(
      List<List<double>> A, List<double> b, int cols) {
    final n = A.length;

    // A^T * A
    final ATA = List.generate(cols, (i) =>
        List.generate(cols, (j) {
          double sum = 0;
          for (int k = 0; k < n; k++) sum += A[k][i] * A[k][j];
          return sum;
        }));

    // A^T * b
    final ATb = List.generate(cols, (i) {
      double sum = 0;
      for (int k = 0; k < n; k++) sum += A[k][i] * b[k];
      return sum;
    });

    // Eliminacja Gaussa z pivotingiem
    final aug = List.generate(cols, (i) => [...ATA[i], ATb[i]]);
    for (int col = 0; col < cols; col++) {
      // Znajdź max pivot
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