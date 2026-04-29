class WorkshopSettings {
  final int id;
  final String name;
  final String phone;
  final String website;
  final String customText;
  final String? logoPath; // ścieżka do pliku logo na urządzeniu

  WorkshopSettings({
    this.id = 0,
    this.name = '',
    this.phone = '',
    this.website = '',
    this.customText = '',
    this.logoPath,
  });

  Map<String, dynamic> toMap() => {
    'id': id == 0 ? null : id,
    'name': name,
    'phone': phone,
    'website': website,
    'customText': customText,
    'logoPath': logoPath,
  };

  factory WorkshopSettings.fromMap(Map<String, dynamic> m) => WorkshopSettings(
    id: m['id'] as int,
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    website: m['website'] as String? ?? '',
    customText: m['customText'] as String? ?? '',
    logoPath: m['logoPath'] as String?,
  );

  WorkshopSettings copyWith({
    String? name,
    String? phone,
    String? website,
    String? customText,
    String? logoPath,
  }) => WorkshopSettings(
    id: id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    customText: customText ?? this.customText,
    logoPath: logoPath ?? this.logoPath,
  );
}