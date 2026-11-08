class Venue {
  final String id;
  final String name;
  final String? address;
  final String? street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  final double? latitude;
  final double? longitude;

  const Venue({
    this.id = '',
    required this.name,
    this.address,
    this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.latitude,
    this.longitude,
  });

  factory Venue.fromMap(String id, Map<String, dynamic> data) {
    String? value(String key) {
      final item = data[key];
      return item is String && item.trim().isNotEmpty ? item.trim() : null;
    }

    double? coordinate(String key) {
      final item = data[key];
      return item is num ? item.toDouble() : null;
    }

    return Venue(
      id: id,
      name: value('name') ?? 'Local sem nome',
      address: value('address'),
      street: value('street'),
      number: value('number'),
      complement: value('complement'),
      neighborhood: value('neighborhood'),
      city: value('city'),
      state: value('state'),
      postcode: value('postcode'),
      country: value('country'),
      latitude: coordinate('latitude'),
      longitude: coordinate('longitude'),
    );
  }
}
