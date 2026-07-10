/// Wersja firmware ESP32 dołączonego do TEJ wersji aplikacji.
///
/// WAŻNE: przy każdym nowym wydaniu firmware:
///   1. Podnieś FW_VERSION w dyno_esp32.ino (const char* FW_VERSION)
///   2. Wyeksportuj .bin (Sketch → Export Compiled Binary)
///   3. Podmień plik assets/firmware/dyno_esp32.bin
///   4. Podnieś wartość poniżej na TĘ SAMĄ wersję co w .ino
///
/// Jeśli te dwie wersje (tu i w .ino) się rozjadą, porównanie wersji
/// w aplikacji będzie kłamać — traktuj to jako jedno źródło prawdy,
/// zapisane w dwóch miejscach ręcznie (ESP32 nie da się odpytać
/// o wersję pliku w assets aplikacji, więc nie da się tego zautomatyzować
/// bez dodatkowego kroku builda).
const String bundledFirmwareVersion = '3.0.0';

/// Ścieżka do firmware w assets — musi być zadeklarowana w pubspec.yaml.
const String bundledFirmwareAssetPath = 'assets/firmware/dyno_esp32.bin';

/// Porównuje wersje w formacie "major.minor.patch".
/// Zwraca: >0 jeśli [a] nowsza niż [b], <0 jeśli starsza, 0 jeśli równe.
/// Nieparsowalne segmenty traktowane jako 0 (nie wywala wyjątku).
int compareFirmwareVersions(String a, String b) {
  final pa = a.trim().split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final pb = b.trim().split('.').map((s) => int.tryParse(s) ?? 0).toList();

  final len = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

/// true jeśli firmware dołączony do aplikacji jest NOWSZY niż to,
/// co aktualnie działa na podłączonym ESP32.
bool isBundledFirmwareNewer(String deviceVersion) {
  return compareFirmwareVersions(bundledFirmwareVersion, deviceVersion) > 0;
}