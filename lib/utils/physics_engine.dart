import 'dart:math';

class PhysicsEngine {
  // Stałe
  static const double gravity = 9.81;
  static const double airDensity = 1.225;
  static const double rollingResistance = 0.015;

  // Liczenie DIN cf (bez zmian)
  static double calculateDINCorrection(double tempC, double pressureHpa) {
    if (pressureHpa <= 0) return 1.0;
    return (1013.0 / pressureHpa) * sqrt((273.15 + tempC) / 293.15);
  }

  /// GŁÓWNA FUNKCJA OBLICZENIOWA - MOC SILNIKA (KM)
  /// Sumuje siły przyspieszenia (koła) i oporów (końcowe straty), gładząc dane.
  static double calculateEngineHp({
    required double v1KmH,
    required double v2KmH,
    required double timeDelta,
    required double weight,
    required double cd,
    required double area,
    required double drivetrainLossFactor, // Static drivetrain guess (e.g., 0.15)
    double smoothedHpFactor = 0.3, // Prosty filtr EMA (0.0 = brak, 1.0 = maks wygładzanie)
    double lastSmoothedHp = 0.0,
  }) {
    if (timeDelta <= 0 || v2KmH <= v1KmH) return lastSmoothedHp;

    double vAvg = ((v1KmH + v2KmH) / 2) / 3.6; // m/s
    double a = ((v2KmH / 3.6) - (v1KmH / 3.6)) / timeDelta;

    // A. Liczymy siłę MOCY NA KOŁACH ( Newtonach)
    double forceAero = 0.5 * airDensity * pow(vAvg, 2) * cd * area;
    double forceRoll = weight * gravity * rollingResistance;
    double forceMass = weight * a;

    double powerWattsWheel = (forceMass + forceAero + forceRoll) * vAvg;
    double hpWheel = powerWattsWheel / 735.498; // KM na kołach

    // B. Przeliczamy na silnik (dodając statyczne straty układu)
    double hpEngineRaw = hpWheel / (1.0 - drivetrainLossFactor);

    // C. PROSTE GŁADZENIE (Filtrowanie EMA)
    // To uleczy 'szum' z obrazka image_4.png
    if (lastSmoothedHp == 0.0) return hpEngineRaw; // Pierwszy punkt

    double smoothedHp = (hpEngineRaw * smoothedHpFactor) + (lastSmoothedHp * (1.0 - smoothedHpFactor));
    return smoothedHp;
  }

  /// Liczenie regresji liniowej dla strat wybiegu (A*x + B)
  /// lossPoints - lista punktów z fazy coasting (X=speed, Y=hpLoss)
  static Map<String, double> calculateLossRegression(List<List<double>> lossPoints) {
    if (lossPoints.length < 2) return {'a': 0, 'b': 0};

    int n = lossPoints.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (var p in lossPoints) {
      sumX += p[0];
      sumY += p[1];
      sumXY += p[0] * p[1];
      sumX2 += p[0] * p[0];
    }

    double a = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    double b = (sumY - a * sumX) / n;

    return {'a': a, 'b': b}; // Zwraca współczynniki prostej strat
  }
}