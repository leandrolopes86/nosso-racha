import 'package:cloud_firestore/cloud_firestore.dart';

class MatchModel {
  String id;
  String teamAName; 
  String teamBName; 
  int goalsA;
  int goalsB;
  String? winnerName; // null se for empate
  DateTime timestamp;
  bool isFinished;
  List<String> queueSnapshot;
  
  // NOVO: Mapas de artilharia (UID do jogador -> Quantidade de gols)
  Map<String, int> scorersA; 
  Map<String, int> scorersB;

  MatchModel({
    required this.id,
    required this.teamAName,
    required this.teamBName,
    this.goalsA = 0,
    this.goalsB = 0,
    this.winnerName,
    required this.timestamp,
    this.isFinished = false,
    this.queueSnapshot = const [],
    this.scorersA = const {}, 
    this.scorersB = const {}, 
  });

  factory MatchModel.fromMap(String id, Map<String, dynamic> data) {
    return MatchModel(
      id: id,
      teamAName: data['team_a'] ?? 'Time A',
      teamBName: data['team_b'] ?? 'Time B',
      goalsA: data['goals_a'] ?? 0,
      goalsB: data['goals_b'] ?? 0,
      winnerName: data['winner'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isFinished: data['is_finished'] ?? false,
      queueSnapshot: List<String>.from(data['queue_snapshot'] ?? []),
      // Conversão segura de Map<String, dynamic> para Map<String, int>
      scorersA: (data['scorers_a'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)) ?? {},
      scorersB: (data['scorers_b'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'team_a': teamAName,
      'team_b': teamBName,
      'goals_a': goalsA,
      'goals_b': goalsB,
      'winner': winnerName,
      'timestamp': Timestamp.fromDate(timestamp),
      'is_finished': isFinished,
      'queue_snapshot': queueSnapshot,
      'scorers_a': scorersA,
      'scorers_b': scorersB,
    };
  }
}