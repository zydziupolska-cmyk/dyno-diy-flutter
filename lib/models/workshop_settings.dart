class WorkshopSettings {
  final int    id;
  final String name;
  final String phone;
  final String website;
  final String customText;
  final String? logoPath;

  // Zakres osi X wykresu — podaj RPM jeśli używasz kalibracji, km/h jeśli nie
  final double chartMinX; // np. 1000 RPM lub 20 km/h
  final double chartMaxX; // np. 6000 RPM lub 200 km/h

  WorkshopSettings({
    this.id          = 0,
    this.name        = '',
    this.phone       = '',
    this.website     = '',
    this.customText  = '',
    this.logoPath,
    this.chartMinX   = 1000.0,  // domyślnie 1000 RPM
    this.chartMaxX   = 6000.0,  // domyślnie 6000 RPM
  });

  Map<String, dynamic> toMap() => {
    'id':          id == 0 ? null : id,
    'name':        name,
    'phone':       phone,
    'website':     website,
    'customText':  customText,
    'logoPath':    logoPath,
    'chartMinX':   chartMinX,
    'chartMaxX':   chartMaxX,
  };

  factory WorkshopSettings.fromMap(Map<String, dynamic> m) => WorkshopSettings(
    id:         m['id']         as int? ?? 0,
    name:       m['name']       as String? ?? '',
    phone:      m['phone']      as String? ?? '',
    website:    m['website']    as String? ?? '',
    customText: m['customText'] as String? ?? '',
    logoPath:   m['logoPath']   as String?,
    chartMinX:  (m['chartMinX'] as num?)?.toDouble() ?? 20.0,
    chartMaxX:  (m['chartMaxX'] as num?)?.toDouble() ?? 200.0,
  );

  WorkshopSettings copyWith({
    String? name,
    String? phone,
    String? website,
    String? customText,
    String? logoPath,
    double? chartMinX,
    double? chartMaxX,
  }) => WorkshopSettings(
    id:         id,
    name:       name        ?? this.name,
    phone:      phone       ?? this.phone,
    website:    website     ?? this.website,
    customText: customText  ?? this.customText,
    logoPath:   logoPath    ?? this.logoPath,
    chartMinX:  chartMinX   ?? this.chartMinX,
    chartMaxX:  chartMaxX   ?? this.chartMaxX,
  );
}