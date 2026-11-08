import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/models/event_model.dart';
import 'package:nosso_racha/models/participant_model.dart';
import 'package:nosso_racha/models/sport_config.dart';

void main() {
  group('SportConfig', () {
    test('defines goalkeeper support and lineup defaults per sport', () {
      expect(SportConfig.fromId('football').hasGoalkeeper, isTrue);
      expect(SportConfig.fromId('futsal').defaultLinePlayersPerTeam, 4);
      expect(SportConfig.fromId('volleyball').hasGoalkeeper, isFalse);
      expect(SportConfig.fromId('basketball').defaultLinePlayersPerTeam, 5);
      expect(SportConfig.fromId('unknown').id, 'football');
    });
  });

  group('EventModel sport configuration', () {
    final start = DateTime(2026, 10, 23, 19);

    EventModel buildEvent({
      String sport = 'football',
      String? locationNote,
      bool allowGoalkeepers = true,
      int externalGoalkeeperSlots = 2,
      double goalkeeperAid = 40,
      double? latitude,
      double? longitude,
      String? street,
      String? addressNumber,
      String? addressComplement,
      String? neighborhood,
      String? city,
      String? state,
      String? postcode,
      String? country,
    }) {
      return EventModel(
        title: 'Teste',
        location: 'Quadra',
        locationNote: locationNote,
        price: 20,
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 2)),
        cancellationDeadline: start.subtract(const Duration(hours: 4)),
        votingOpensAt: start.subtract(const Duration(days: 1)),
        numberOfTeams: 4,
        linePlayersPerTeam: 5,
        status: 'scheduled',
        createdBy: 'organizer',
        groupId: 'group-1',
        sport: sport,
        allowGoalkeepers: allowGoalkeepers,
        externalGoalkeeperSlots: externalGoalkeeperSlots,
        goalkeeperAid: goalkeeperAid,
        latitude: latitude,
        longitude: longitude,
        street: street,
        addressNumber: addressNumber,
        addressComplement: addressComplement,
        neighborhood: neighborhood,
        city: city,
        state: state,
        postcode: postcode,
        country: country,
      );
    }

    test(
      'excludes goalkeeper positions and capacity in non-goalkeeper sports',
      () {
        final event = buildEvent(
          sport: 'volleyball',
          allowGoalkeepers: false,
          externalGoalkeeperSlots: 0,
          goalkeeperAid: 0,
        );

        expect(event.sportHasGoalkeeper, isFalse);
        expect(event.maxGoalkeepers, 0);
        expect(event.maxLinePlayers, 20);
        expect(event.totalCapacity, 20);
      },
    );

    test('serializes sport and goalkeeper event settings', () {
      final info = buildEvent().toMap()['info'] as Map<String, dynamic>;

      expect(info['sport'], 'football');
      expect(info['external_goalkeeper_slots'], 2);
      expect(info['goalkeeper_aid'], 40);
    });

    test('round-trips an optional location note', () {
      final event = EventModel.fromMap(
        'event-1',
        buildEvent(locationNote: 'Quadra A').toMap(),
      );

      expect(event.locationNote, 'Quadra A');
    });

    test('round-trips optional event coordinates', () {
      final event = EventModel.fromMap(
        'event-1',
        buildEvent(
          latitude: -23.5505,
          longitude: -46.6333,
          street: 'Rua das Flores',
          addressNumber: '42',
          addressComplement: 'Bloco A',
          neighborhood: 'Centro',
          city: 'São Paulo',
          state: 'SP',
          postcode: '01000-000',
          country: 'Brasil',
        ).toMap(),
      );

      expect(event.latitude, -23.5505);
      expect(event.longitude, -46.6333);
      expect(event.street, 'Rua das Flores');
      expect(event.addressNumber, '42');
      expect(event.addressComplement, 'Bloco A');
      expect(event.neighborhood, 'Centro');
      expect(event.city, 'São Paulo');
      expect(event.state, 'SP');
      expect(event.postcode, '01000-000');
      expect(event.country, 'Brasil');
    });
  });

  test('participant external status survives Firestore serialization', () {
    final participant = ParticipantModel(
      uid: 'external-player',
      name: 'Player',
      status: 'active',
      registeredAt: DateTime(2026, 10, 23),
      isExternal: true,
    );

    expect(ParticipantModel.fromMap(participant.toMap()).isExternal, isTrue);
  });

  test(
    'goalkeeper payment state survives serialization without exposing Pix key',
    () {
      final participant = ParticipantModel(
        uid: 'goalkeeper-1',
        name: 'Goalkeeper',
        status: 'active',
        registeredAt: DateTime(2026, 10, 23),
        roleInMatch: 'goalkeeper',
        goaliePaymentStatus: 'pending_confirmation',
        pixKey: 'private@example.com',
      );
      final map = participant.toMap();

      expect(map['goalie_payment_status'], 'pending_confirmation');
      expect(map.containsKey('pix_key'), isFalse);
      expect(
        ParticipantModel.fromMap(map).goaliePaymentStatus,
        'pending_confirmation',
      );
    },
  );
}
