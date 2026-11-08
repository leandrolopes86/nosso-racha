import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/match_model.dart';
import '../models/event_model.dart';

class MatchService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // --- LEITURA ---
  Stream<DocumentSnapshot> getEventQueueStream(String eventId) {
    return _firestore.collection('events').doc(eventId).snapshots();
  }

  Stream<QuerySnapshot> getMatchesHistoryStream(String eventId) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .collection('matches')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // --- LÓGICA DE JOGO ---

  Future<void> initializeQueueIfNotExists(EventModel event) async {
    final docRef = _firestore.collection('events').doc(event.id);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) return;
    
    final data = docSnapshot.data() as Map<String, dynamic>;
    
    if ((data.containsKey('match_queue') && (data['match_queue'] as List).isNotEmpty) || 
        data['current_match_data'] != null) {
      return;
    }

    List<String> initialQueue = [];
    int numTeams = event.numberOfTeams;
    for (int i = 1; i <= numTeams; i++) {
      initialQueue.add("Time $i");
    }

    // Inicia o primeiro jogo
    await startNextMatch(event.id!, initialQueue);
  }

  Future<void> startNextMatch(String eventId, List<String> currentQueue) async {
    if (currentQueue.length < 2) return;

    final teamA = currentQueue[0];
    final teamB = currentQueue[1];

    final newMatch = MatchModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      teamAName: teamA,
      teamBName: teamB,
      timestamp: DateTime.now(),
      isFinished: false,
      queueSnapshot: [], // Vazio enquanto joga
    );

    await _firestore.collection('events').doc(eventId).update({
      'match_queue': currentQueue, 
      'current_match_data': newMatch.toMap(),
    });
  }

  Future<void> updateScore(String eventId, int goalsA, int goalsB) async {
    await _firestore.collection('events').doc(eventId).update({
      'current_match_data.goals_a': goalsA,
      'current_match_data.goals_b': goalsB,
    });
  }

  // --- FINALIZA A PARTIDA E SALVA SNAPSHOT ---
  Future<void> finishMatch(String eventId, MatchModel match, List<String> currentQueue, String? winnerPriority) async {
    _isLoading = true; notifyListeners();

    try {
      final docRef = _firestore.collection('events').doc(eventId);
      
      // 1. Prepara dados do jogo finalizado
      match.isFinished = true;
      if (match.goalsA > match.goalsB) {
        match.winnerName = match.teamAName;
      } else if (match.goalsB > match.goalsA) match.winnerName = match.teamBName;
      else match.winnerName = "Empate"; 

      // 2. SALVA O SNAPSHOT DA FILA (Como ela estava DURANTE esse jogo)
      // Isso é crucial para a reversão funcionar perfeitamente
      match.queueSnapshot = List.from(currentQueue);

      // 3. Salva no histórico
      await docRef.collection('matches').add(match.toMap());

      // 4. Calcula a NOVA fila para o PRÓXIMO jogo
      List<String> newQueue = List.from(currentQueue);
      String teamA = match.teamAName;
      String teamB = match.teamBName;

      // Remove os times que jogaram do topo
      newQueue.remove(teamA);
      newQueue.remove(teamB);

      if (match.goalsA != match.goalsB) {
        // Vitória: Vencedor volta pro topo, Perdedor vai pro fim
        String winner = match.goalsA > match.goalsB ? teamA : teamB;
        String loser = match.goalsA > match.goalsB ? teamB : teamA;
        newQueue.insert(0, winner); 
        newQueue.add(loser);        
      } else {
        // Empate: Ambos pro final, respeitando prioridade
        String priorityTeam = winnerPriority ?? teamA; 
        String otherTeam = (priorityTeam == teamA) ? teamB : teamA;
        newQueue.add(priorityTeam); 
        newQueue.add(otherTeam);
      }

      // 5. Inicia o próximo
      await startNextMatch(eventId, newQueue);

    } catch (e) {
      throw Exception("Erro ao finalizar partida: $e");
    } finally {
      _isLoading = false; notifyListeners();
    }
  }
}