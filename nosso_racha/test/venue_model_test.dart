import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/venue_model.dart';

void main() {
  group('Venue', () {
    test('loads address and coordinates from a Firestore map', () {
      final venue = Venue.fromMap('venue-1', {
        'name': 'Arena Central',
        'address': 'Rua das Flores, 10',
        'city': 'Juazeiro',
        'latitude': -9.4167,
        'longitude': -40.5033,
      });

      expect(venue.id, 'venue-1');
      expect(venue.name, 'Arena Central');
      expect(venue.address, 'Rua das Flores, 10');
      expect(venue.city, 'Juazeiro');
      expect(venue.latitude, -9.4167);
      expect(venue.longitude, -40.5033);
    });

    test('handles optional address data and coordinates', () {
      final venue = Venue.fromMap('venue-2', {'name': 'Arena Norte'});

      expect(venue.name, 'Arena Norte');
      expect(venue.address, isNull);
      expect(venue.latitude, isNull);
      expect(venue.longitude, isNull);
    });
  });
}
