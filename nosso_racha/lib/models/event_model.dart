import 'package:cloud_firestore/cloud_firestore.dart';
import 'participant_model.dart';
import 'sport_config.dart';

class EventModel {
  final String? id;
  final String title;
  final String location;
  final String? locationNote;
  final double price;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final DateTime cancellationDeadline;

  final DateTime votingOpensAt;

  final int numberOfTeams;
  final int linePlayersPerTeam;
  final String sport;
  final int externalGoalkeeperSlots;
  final double goalkeeperAid;
  final String status;
  final String createdBy;
  final String? groupId; // NOVO: ID do grupo vinculado
  final String? groupName;
  final double? latitude;
  final double? longitude;
  final String? street;
  final String? addressNumber;
  final String? addressComplement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  final List<ParticipantModel> participants;
  final List<ParticipantModel> closingList; // Lista independente de fechamento

  // Dados de Sorteio
  final Map<String, dynamic>? teamsDistribution; // Times Prontos
  final Map<String, dynamic>? tiersDistribution; // Níveis Definidos

  // --- NOVAS PROPRIEDADES DE VISIBILIDADE E REGRAS ---
  final String visibility; // 'public', 'moderated', 'private'
  final bool allowLinePlayers;
  final bool allowGoalkeepers;

  EventModel({
    this.id,
    required this.title,
    required this.location,
    this.locationNote,
    required this.price,
    required this.startDateTime,
    required this.endDateTime,
    required this.cancellationDeadline,
    required this.votingOpensAt,
    required this.numberOfTeams,
    required this.linePlayersPerTeam,
    this.sport = 'football',
    this.externalGoalkeeperSlots = 0,
    this.goalkeeperAid = 0,
    required this.status,
    required this.createdBy,
    this.groupId, // NOVO
    this.groupName,
    this.latitude,
    this.longitude,
    this.street,
    this.addressNumber,
    this.addressComplement,
    this.neighborhood,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.participants = const [],
    this.closingList = const [],
    this.teamsDistribution,
    this.tiersDistribution,
    this.visibility = 'public',
    this.allowLinePlayers = true,
    this.allowGoalkeepers = true,
  });

  bool get sportHasGoalkeeper => SportConfig.fromId(sport).hasGoalkeeper;
  String get sportLabel => SportConfig.fromId(sport).label;
  int get maxGoalkeepers => sportHasGoalkeeper ? numberOfTeams : 0;
  int get maxLinePlayers => numberOfTeams * linePlayersPerTeam;
  int get totalCapacity => maxGoalkeepers + maxLinePlayers;
  int get maxExternalGoalkeeperSlots =>
      externalGoalkeeperSlots.clamp(0, maxGoalkeepers);

  int get confirmedCount =>
      participants.where((p) => p.status == 'active').length;

  factory EventModel.fromMap(String id, Map<String, dynamic> map) {
    final info = map['info'] ?? {};
    final audit = map['audit'] ?? {};

    final List<dynamic> rawParticipants = map['participants'] ?? [];
    final parsedParticipants = rawParticipants
        .map((p) => ParticipantModel.fromMap(p as Map<String, dynamic>))
        .toList();

    // Lê a lista de fechamento isolada do banco
    final List<dynamic> rawClosing = map['closing_list'] ?? [];
    List<ParticipantModel> parsedClosing = rawClosing
        .map((p) => ParticipantModel.fromMap(p as Map<String, dynamic>))
        .toList();

    // Fallback de segurança para rachas antigos que já foram finalizados antes desta atualização
    if (parsedClosing.isEmpty && info['status'] == 'finished') {
      parsedClosing = List.from(parsedParticipants);
    }

    DateTime votingOpen;
    if (info['voting_opens_at'] != null) {
      votingOpen = (info['voting_opens_at'] as Timestamp).toDate();
    } else {
      votingOpen = DateTime.now().subtract(const Duration(minutes: 1));
    }

    return EventModel(
      id: id,
      title: info['title'] ?? '',
      location: info['location'] ?? '',
      locationNote: _stringValue(info['location_note']),
      price: (info['price'] ?? 0).toDouble(),
      numberOfTeams: info['number_of_teams'] ?? 2,
      linePlayersPerTeam: info['line_players_per_team'] ?? 5,
      sport: info['sport'] ?? 'football',
      externalGoalkeeperSlots:
          info['external_goalkeeper_slots'] ??
          ((info['allow_goalkeepers'] ?? true)
              ? (info['number_of_teams'] ?? 2)
              : 0),
      goalkeeperAid: (info['goalkeeper_aid'] ?? 0).toDouble(),
      startDateTime: (info['start_date_time'] as Timestamp).toDate(),
      endDateTime: (info['end_date_time'] as Timestamp).toDate(),
      cancellationDeadline: (info['cancellation_deadline'] as Timestamp)
          .toDate(),
      votingOpensAt: votingOpen,
      status: info['status'] ?? 'scheduled',
      createdBy: audit['created_by'] ?? '',
      groupId: info['group_id'] ?? map['group_id'],
      groupName: _stringValue(info['group_name'] ?? map['group_name']),
      latitude: _coordinateValue(info['latitude'] ?? map['latitude']),
      longitude: _coordinateValue(info['longitude'] ?? map['longitude']),
      street: _stringValue(info['street'] ?? map['street']),
      addressNumber: _stringValue(
        info['address_number'] ?? map['address_number'],
      ),
      addressComplement: _stringValue(
        info['address_complement'] ?? map['address_complement'],
      ),
      neighborhood: _stringValue(info['neighborhood'] ?? map['neighborhood']),
      city: _stringValue(info['city'] ?? map['city']),
      state: _stringValue(info['state'] ?? map['state']),
      postcode: _stringValue(info['postcode'] ?? map['postcode']),
      country: _stringValue(info['country'] ?? map['country']),
      visibility: info['visibility'] ?? 'public', // Lendo do banco
      allowLinePlayers: info['allow_line_players'] ?? true, // Lendo do banco
      allowGoalkeepers: info['allow_goalkeepers'] ?? true, // Lendo do banco
      participants: parsedParticipants,
      closingList: parsedClosing,
      teamsDistribution: map['teams_distribution'],
      tiersDistribution: map['tiers_distribution'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'info': {
        'title': title,
        'location': location,
        'location_note': locationNote,
        'price': price,
        'number_of_teams': numberOfTeams,
        'line_players_per_team': linePlayersPerTeam,
        'sport': sport,
        'external_goalkeeper_slots': externalGoalkeeperSlots,
        'goalkeeper_aid': goalkeeperAid,
        'start_date_time': Timestamp.fromDate(startDateTime),
        'end_date_time': Timestamp.fromDate(endDateTime),
        'cancellation_deadline': Timestamp.fromDate(cancellationDeadline),
        'voting_opens_at': Timestamp.fromDate(votingOpensAt),
        'status': status,
        'group_id': groupId,
        'group_name': groupName,
        'latitude': latitude,
        'longitude': longitude,
        'street': street,
        'address_number': addressNumber,
        'address_complement': addressComplement,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
        'postcode': postcode,
        'country': country,
        'visibility': visibility, // Salvando no banco
        'allow_line_players': allowLinePlayers, // Salvando no banco
        'allow_goalkeepers': allowGoalkeepers, // Salvando no banco
      },
      'audit': {
        'created_by': createdBy,
        'created_at': FieldValue.serverTimestamp(),
      },
      'participants': participants.map((p) => p.toMap()).toList(),
      'closing_list': closingList.map((p) => p.toMap()).toList(),
      'teams_distribution': teamsDistribution,
      'tiers_distribution': tiersDistribution,
    };
  }

  static double? _coordinateValue(dynamic value) =>
      value is num ? value.toDouble() : null;

  static String? _stringValue(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
