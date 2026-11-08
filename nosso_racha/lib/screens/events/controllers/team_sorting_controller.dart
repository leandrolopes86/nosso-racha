import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/event_model.dart';
import '../../../models/participant_model.dart';
import '../../../models/user_model.dart';

class TeamSortingController extends ChangeNotifier {
  EventModel event;
  final UserModel? currentUser;

  List<ParticipantModel> goalkeepers = [];
  List<ParticipantModel> linePlayers = [];
  List<Map<String, dynamic>> activeUsers = [];
  List<List<ParticipantModel>> tiers = [];
  bool tiersSaved = false;
  bool tiersGenerated = false;
  List<List<ParticipantModel>> generatedTeams = [];
  bool teamsGenerated = false;
  bool teamsSaved = false;
  bool isLoading = true;
  bool includeGoalkeepers = false;
  bool considerPositions = false;
  Map<String, double> playerRatings = {};
  Map<String, List<String>> playerPositions = {};
  bool _isDisposed = false;

  StreamSubscription<DocumentSnapshot>? _eventSubscription;
  StreamSubscription? _presenceSubscription;

  TeamSortingController({required this.event, required this.currentUser}) {
    _initializeListsLocally();
    _setupRealtimeSync();
    _setupPresenceSync();
    _fetchUserData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _presenceSubscription?.cancel(); // Cancela o listener da presença!
    setPresence(false);
    _eventSubscription?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void _setupPresenceSync() {
    _presenceSubscription = FirebaseFirestore.instance
        .collection('events')
        .doc(event.id)
        .collection('online_users')
        .snapshots()
        .listen((snapshot) {
          if (_isDisposed) return; // Segurança extra
          activeUsers = snapshot.docs.map((doc) => doc.data()).toList();
          notifyListeners();
        });
  }

  Future<void> setPresence(bool isPresent) async {
    // Adicione esta checagem de segurança logo no início
    if (currentUser == null) {
      debugPrint("Tentativa de setPresence sem usuário logado. Ignorado.");
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .collection('online_users')
          .doc(
            currentUser!.uid,
          ); // currentUser! aqui é seguro pois checamos antes

      if (isPresent) {
        await docRef.set({
          'name': currentUser!.nickname.isNotEmpty
              ? currentUser!.nickname
              : currentUser!.name,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.delete();
      }
    } catch (e) {
      debugPrint("Erro ao atualizar presença: $e");
    }
  }
  // --- INICIALIZAÇÃO ---

  void _initializeListsLocally() {
    final confirmed = event.participants
        .where((p) => p.status == 'active')
        .toList();
    final allGks = confirmed
        .where((p) => p.roleInMatch == 'goalkeeper')
        .toList();
    final allLine = confirmed
        .where((p) => p.roleInMatch != 'goalkeeper')
        .toList();

    goalkeepers = (allGks.length > event.maxGoalkeepers)
        ? allGks.sublist(0, event.maxGoalkeepers)
        : allGks;
    linePlayers = (allLine.length > event.maxLinePlayers)
        ? allLine.sublist(0, event.maxLinePlayers)
        : allLine;

    if (tiers.isEmpty) tiers = List.generate(event.numberOfTeams, (_) => []);
    if (generatedTeams.isEmpty)
      generatedTeams = List.generate(event.numberOfTeams, (_) => []);
  }

  void _setupRealtimeSync() async {
    isLoading = true;
    notifyListeners();

    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(event.groupId)
          .collection('settings')
          .doc('general')
          .get();
      if (settingsDoc.exists && settingsDoc.data() != null) {
        final sData = settingsDoc.data() as Map<String, dynamic>;
        includeGoalkeepers = sData['default_include_goalkeepers'] ?? false;
        considerPositions = sData['default_consider_positions'] ?? false;
      }

      _eventSubscription = FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              _processEventUpdate(snapshot.data() as Map<String, dynamic>);
            }
          });
    } catch (e) {
      print("Erro no sync: $e");
      isLoading = false;
      notifyListeners();
    }
  }

  void _processEventUpdate(Map<String, dynamic> data) {
    if (data.containsKey('config_include_goalkeepers'))
      includeGoalkeepers =
          data['config_include_goalkeepers'] ?? includeGoalkeepers;
    if (data.containsKey('config_consider_positions'))
      considerPositions =
          data['config_consider_positions'] ?? considerPositions;

    final eventId = event.id ?? '';
    event = EventModel.fromMap(eventId, data);

    final participantsRaw = List<Map<String, dynamic>>.from(
      data['participants'] ?? [],
    );
    final participants = participantsRaw
        .map((p) => ParticipantModel.fromMap(p))
        .toList();

    final confirmed = participants.where((p) => p.status == 'active').toList();
    final allGks = confirmed
        .where((p) => p.roleInMatch == 'goalkeeper')
        .toList();
    final allLine = confirmed
        .where((p) => p.roleInMatch != 'goalkeeper')
        .toList();

    goalkeepers = (allGks.length > event.maxGoalkeepers)
        ? allGks.sublist(0, event.maxGoalkeepers)
        : allGks;
    linePlayers = (allLine.length > event.maxLinePlayers)
        ? allLine.sublist(0, event.maxLinePlayers)
        : allLine;

    // Sincroniza Níveis
    bool remoteTiersLocked = data['tiers_locked'] ?? false;
    Map<String, dynamic> tiersMap = data['tiers_distribution'] != null
        ? Map<String, dynamic>.from(data['tiers_distribution'])
        : {};

    if (tiersMap.isNotEmpty) {
      tiers = [];
      final sortedKeys = tiersMap.keys.toList()..sort();
      for (var key in sortedKeys) {
        final list = tiersMap[key];
        if (list is List)
          tiers.add(list.map((p) => ParticipantModel.fromMap(p)).toList());
      }
      tiersGenerated = true;
    } else {
      if (!remoteTiersLocked && !tiersSaved) {
        if (tiers.isEmpty ||
            (tiers.length != event.numberOfTeams &&
                tiers.length != event.linePlayersPerTeam)) {
          tiers = List.generate(event.linePlayersPerTeam, (_) => []);
          tiersGenerated = false;
        }
      }
    }
    tiersSaved = remoteTiersLocked;

    // Sincroniza Times
    bool remoteTeamsLocked = data['teams_locked'] ?? false;
    Map<String, dynamic> teamsMapData = data['teams_distribution'] != null
        ? Map<String, dynamic>.from(data['teams_distribution'])
        : {};

    if (teamsMapData.isNotEmpty) {
      generatedTeams = List.generate(event.numberOfTeams, (_) => []);
      bool hasTeams = false;
      teamsMapData.forEach((key, value) {
        try {
          int teamNum =
              int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          int index = teamNum - 1;
          if (index >= 0 && index < event.numberOfTeams && value is List) {
            generatedTeams[index] = value
                .map((p) => ParticipantModel.fromMap(p))
                .toList();
            if (generatedTeams[index].isNotEmpty) hasTeams = true;
          }
        } catch (e) {
          debugPrint('Ignorando participante inválido do time "$key": $e');
        }
      });
      if (hasTeams) teamsGenerated = true;
    } else {
      if (!remoteTeamsLocked) {
        generatedTeams = List.generate(event.numberOfTeams, (_) => []);
        teamsGenerated = false;
      }
    }
    teamsSaved = remoteTeamsLocked;

    isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchUserData() async {
    await Future.delayed(Duration.zero);
    List<Future> futures = [];
    var allPlayers = [...linePlayers, ...goalkeepers];
    for (var p in allPlayers) futures.add(_fetchSingleUserData(p.uid));
    await Future.wait(futures);
    notifyListeners();
  }

  Future<void> _fetchSingleUserData(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) {
        var data = doc.data();
        var stats = data?['football_stats'] as Map<String, dynamic>?;

        double r = (stats?['rating'] ?? 1.0).toDouble();

        playerRatings[uid] = r;
        List<String> pos = List<String>.from(stats?['positions'] ?? []);
        playerPositions[uid] = pos;
      }
    } catch (e) {
      debugPrint("Erro ao buscar stats do jogador $uid: $e");
    }
  }

  // --- LÓGICA DE NEGÓCIO ---

  Future<void> generateTiers() async {
    await _fetchUserData();

    // 2. Verificação de integridade: se algum jogador não tiver rating, atribuímos um padrão
    for (var p in linePlayers) {
      if (!playerRatings.containsKey(p.uid)) {
        playerRatings[p.uid] = 6.0; // Nota padrão para evitar erros
      }
    }

    if (tiersSaved) return;

    int compareByRating(ParticipantModel a, ParticipantModel b) {
      double rA = playerRatings[a.uid] ?? 6.0;
      double rB = playerRatings[b.uid] ?? 6.0;
      int cmp = rB.compareTo(rA);
      if (cmp == 0) return a.name.compareTo(b.name);
      return cmp;
    }

    tiers.clear();
    int numTeams = event.numberOfTeams;
    List<ParticipantModel> pool = List.from(linePlayers);

    if (!considerPositions) {
      pool.sort(compareByRating);
      int playersPerTeam = event.linePlayersPerTeam;
      for (int i = 0; i < playersPerTeam; i++) {
        List<ParticipantModel> tierList = [];
        if (pool.isNotEmpty) {
          int count = (pool.length >= numTeams) ? numTeams : pool.length;
          tierList = pool.take(count).toList();
          pool.removeRange(0, count);
        }
        tiers.add(tierList);
      }
      tiersGenerated = true;
      notifyListeners();
      return;
    }

    pool.sort(compareByRating);
    List<ParticipantModel> tier1 = [];
    if (pool.length >= numTeams) {
      tier1 = pool.take(numTeams).toList();
      pool.removeRange(0, numTeams);
    } else {
      tier1 = List.from(pool);
      pool.clear();
    }
    tiers.add(tier1);

    if (pool.isNotEmpty) {
      List<ParticipantModel> defenders = [];
      List<ParticipantModel> others = [];

      for (var p in pool) {
        List<String> pos = playerPositions[p.uid] ?? [];
        if (pos.contains('Zagueiro') || pos.contains('Defensor')) {
          defenders.add(p);
        } else {
          others.add(p);
        }
      }

      defenders.sort(compareByRating);
      others.sort(compareByRating);

      while (defenders.length >= numTeams) {
        List<ParticipantModel> defenderTier = defenders.take(numTeams).toList();
        defenders.removeRange(0, numTeams);
        tiers.add(defenderTier);
      }

      List<ParticipantModel> remainingPool = [...defenders, ...others];
      remainingPool.sort(compareByRating);

      while (remainingPool.isNotEmpty) {
        int count = (remainingPool.length >= numTeams)
            ? numTeams
            : remainingPool.length;
        List<ParticipantModel> nextTier = remainingPool.take(count).toList();
        remainingPool.removeRange(0, count);
        tiers.add(nextTier);
      }
    }

    while (tiers.length < event.linePlayersPerTeam) {
      tiers.add([]);
    }

    tiersGenerated = true;

    await FirebaseFirestore.instance.collection('events').doc(event.id).update({
      'tiers_distribution': tiers.asMap().map(
        (i, list) =>
            MapEntry('Nivel ${i + 1}', list.map((p) => p.toMap()).toList()),
      ),
    });
    notifyListeners();
  }

  void generateTeamsFromTiers() {
    int numTeams = event.numberOfTeams;
    generatedTeams = List.generate(numTeams, (_) => []);

    // 1. Goleiros
    if (includeGoalkeepers) {
      var gksToDistribute = List<ParticipantModel>.from(goalkeepers)..shuffle();
      for (int i = 0; i < gksToDistribute.length; i++) {
        generatedTeams[i % numTeams].add(gksToDistribute[i]);
      }
    }

    // 2. Linha (Nível por Nível)
    for (var tier in tiers) {
      var playersInTier = List<ParticipantModel>.from(tier)..shuffle();
      List<int> availableTeamIndices = List.generate(numTeams, (i) => i)
        ..shuffle();

      for (var player in playersInTier) {
        if (availableTeamIndices.isEmpty) {
          availableTeamIndices = List.generate(numTeams, (i) => i)..shuffle();
        }
        int teamIndex = availableTeamIndices.removeAt(0);
        generatedTeams[teamIndex].add(player);
      }
    }

    teamsGenerated = true;
    teamsSaved = false;
    notifyListeners();
  }

  int getPlayerTier(String uid) {
    for (int i = 0; i < tiers.length; i++) {
      if (tiers[i].any((p) => p.uid == uid)) return i + 1;
    }
    return 0;
  }

  // --- ACTIONS ---

  Future<String?> saveTiers() async {
    if (currentUser == null || !currentUser!.canGenerateTiers)
      return "Sem permissão.";

    int maxPerTier = event.numberOfTeams;
    for (int i = 0; i < tiers.length; i++) {
      if (tiers[i].length > maxPerTier) {
        return "Erro: O Nível ${i + 1} tem ${tiers[i].length} jogadores. O máximo permitido é $maxPerTier.";
      }
    }

    try {
      Map<String, dynamic> tiersMap = {};
      for (int i = 0; i < tiers.length; i++) {
        tiersMap['Nivel ${i + 1}'] = tiers[i].map((p) => p.toMap()).toList();
      }
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({
            'tiers_distribution': tiersMap,
            'config_include_goalkeepers': includeGoalkeepers,
            'config_consider_positions': considerPositions,
            'tiers_locked': true,
          });
      tiersSaved = true;
      notifyListeners();
      return null;
    } catch (e) {
      return "Erro ao salvar níveis: $e";
    }
  }

  Future<String?> saveTeams() async {
    if (currentUser == null || !currentUser!.canSortTeams)
      return "Sem permissão.";
    if (!tiersSaved) return "Níveis estão abertos! Salve-os primeiro.";

    int maxLimit = event.linePlayersPerTeam + (includeGoalkeepers ? 1 : 0);
    for (int i = 0; i < generatedTeams.length; i++) {
      if (generatedTeams[i].length > maxLimit) {
        return "Erro: O Time ${i + 1} excede o limite ($maxLimit).";
      }
    }

    try {
      Map<String, dynamic> teamsMap = {};
      for (int i = 0; i < generatedTeams.length; i++) {
        teamsMap['Time ${i + 1}'] = generatedTeams[i]
            .map((p) => p.toMap())
            .toList();
      }
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .update({'teams_distribution': teamsMap, 'teams_locked': true});
      teamsSaved = true;
      notifyListeners();
      return null;
    } catch (e) {
      return "Erro ao salvar times: $e";
    }
  }

  Future<void> reopenTiers() async {
    if (currentUser == null || !currentUser!.canReopenTiers) return;
    await FirebaseFirestore.instance.collection('events').doc(event.id).update({
      'tiers_locked': false,
    });
    tiersSaved = false;
    notifyListeners();
  }

  Future<void> reopenTeams() async {
    if (currentUser == null || !currentUser!.canReopenTeams) return;
    await FirebaseFirestore.instance.collection('events').doc(event.id).update({
      'teams_locked': false,
      'teams_distribution': {},
    });
    teamsSaved = false;
    teamsGenerated = false;
    generatedTeams = [];
    notifyListeners();
  }

  // --- MANIPULAÇÃO LOCAL E ORDENAÇÃO MANUAL ---

  Future<void> movePlayerBetweenTiers(
    ParticipantModel player,
    int targetTierIndex,
  ) async {
    for (var tier in tiers) tier.removeWhere((p) => p.uid == player.uid);
    tiers[targetTierIndex].add(player);
    await FirebaseFirestore.instance.collection('events').doc(event.id).update({
      'tiers_distribution': tiers.asMap().map(
        (i, list) =>
            MapEntry('Nivel ${i + 1}', list.map((p) => p.toMap()).toList()),
      ),
    });
    notifyListeners();
  }

  bool movePlayerBetweenTeams(ParticipantModel player, int targetTeamIndex) {
    if (currentUser == null || !currentUser!.canSortTeams) return true;

    if (includeGoalkeepers && player.roleInMatch == 'goalkeeper') {
      int targetGkIndex = generatedTeams[targetTeamIndex].indexWhere(
        (p) => p.roleInMatch == 'goalkeeper',
      );
      if (targetGkIndex != -1) {
        ParticipantModel targetGk =
            generatedTeams[targetTeamIndex][targetGkIndex];
        if (targetGk.uid != player.uid) {
          return false;
        }
      }
    }

    _performMove(player, targetTeamIndex);
    return true;
  }

  void reorderPlayerWithinTeam(
    ParticipantModel player,
    int teamIndex,
    int direction,
  ) {
    if (currentUser == null || !currentUser!.canSortTeams) return;

    final team = generatedTeams[teamIndex];
    final gks = team.where((p) => p.roleInMatch == 'goalkeeper').toList();
    final lines = team.where((p) => p.roleInMatch != 'goalkeeper').toList();

    List<ParticipantModel> targetList = player.roleInMatch == 'goalkeeper'
        ? gks
        : lines;

    int index = targetList.indexWhere((p) => p.uid == player.uid);
    if (index == -1) return;

    int newIndex = index + direction;
    if (newIndex >= 0 && newIndex < targetList.length) {
      final temp = targetList.removeAt(index);
      targetList.insert(newIndex, temp);
      generatedTeams[teamIndex] = [...gks, ...lines];
      notifyListeners();
    }
  }

  void forceSwapGoalkeepers(ParticipantModel player, int targetTeamIndex) {
    int targetGkIndex = generatedTeams[targetTeamIndex].indexWhere(
      (p) => p.roleInMatch == 'goalkeeper',
    );
    if (targetGkIndex != -1) {
      ParticipantModel targetGk =
          generatedTeams[targetTeamIndex][targetGkIndex];

      int sourceTeamIndex = -1;
      for (int i = 0; i < generatedTeams.length; i++) {
        if (generatedTeams[i].any((p) => p.uid == player.uid)) {
          sourceTeamIndex = i;
          break;
        }
      }

      if (sourceTeamIndex != -1) {
        generatedTeams[sourceTeamIndex].removeWhere((p) => p.uid == player.uid);
        generatedTeams[targetTeamIndex].removeWhere(
          (p) => p.uid == targetGk.uid,
        );

        generatedTeams[sourceTeamIndex].insert(0, targetGk);
        generatedTeams[targetTeamIndex].insert(0, player);
        notifyListeners();
      }
    }
  }

  void _performMove(ParticipantModel player, int targetTeamIndex) {
    for (var team in generatedTeams)
      team.removeWhere((p) => p.uid == player.uid);

    if (player.roleInMatch == 'goalkeeper') {
      generatedTeams[targetTeamIndex].insert(0, player);
    } else {
      generatedTeams[targetTeamIndex].add(player);
    }

    notifyListeners();
  }

  void reorderTeams(int oldIndex, int newIndex) {
    if (currentUser == null || !currentUser!.canSortTeams) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final List<ParticipantModel> team = generatedTeams.removeAt(oldIndex);
    generatedTeams.insert(newIndex, team);
    notifyListeners();
  }

  // --- NOVA FUNÇÃO: ORDENAR TIME ESPECÍFICO POR NÍVEL ---
  void sortTeamByTier(int teamIndex) {
    if (currentUser == null || !currentUser!.canSortTeams) return;

    generatedTeams[teamIndex].sort((a, b) {
      // 1. Goleiros no topo
      if (a.roleInMatch == 'goalkeeper' && b.roleInMatch != 'goalkeeper')
        return -1;
      if (a.roleInMatch != 'goalkeeper' && b.roleInMatch == 'goalkeeper')
        return 1;

      // 2. Ordena pelo nível original do Pote
      int tierA = getPlayerTier(a.uid);
      int tierB = getPlayerTier(b.uid);

      int sortTierA = tierA > 0 ? tierA : 999;
      int sortTierB = tierB > 0 ? tierB : 999;

      if (sortTierA != sortTierB) return sortTierA.compareTo(sortTierB);

      // 3. Desempate alfabético
      return a.name.compareTo(b.name);
    });

    notifyListeners();
  }

  void toggleGoalkeepers(bool val) {
    if (currentUser != null && currentUser!.canSortTeams) {
      includeGoalkeepers = val;
      notifyListeners();
    }
  }

  void togglePositions(bool val) {
    if (currentUser != null && currentUser!.canGenerateTiers) {
      considerPositions = val;
      notifyListeners();
    }
  }

  // --- LÓGICA INTELIGENTE DE SLOTS (VAGAS) PARA TELA E EXPORTAÇÃO ---
  List<ParticipantModel?> getSlottedLinePlayers(List<ParticipantModel> team) {
    final lines = team.where((p) => p.roleInMatch != 'goalkeeper').toList();
    int maxSlots = event.linePlayersPerTeam;

    // Se o time estiver completo ou acima do limite, ignora os slots vazios e lista em sequência
    if (lines.length >= maxSlots) {
      return lines;
    }

    List<ParticipantModel?> slotted = List.filled(maxSlots, null);

    // Encaixa os jogadores em seus níveis, ou no próximo buraco mais próximo se houver conflito
    for (var player in lines) {
      int tier = getPlayerTier(player.uid);
      int desiredSlot = (tier > 0 ? tier : 1) - 1;

      if (desiredSlot >= maxSlots) desiredSlot = maxSlots - 1;

      bool placed = false;
      // Procura primeiro para baixo
      for (int i = desiredSlot; i < maxSlots; i++) {
        if (slotted[i] == null) {
          slotted[i] = player;
          placed = true;
          break;
        }
      }
      // Se não achou, procura para cima (em slots anteriores)
      if (!placed) {
        for (int i = 0; i < desiredSlot; i++) {
          if (slotted[i] == null) {
            slotted[i] = player;
            placed = true;
            break;
          }
        }
      }
    }
    return slotted;
  }

  // --- TEXTOS DE COMPARTILHAMENTO ---

  String generateTiersText() {
    StringBuffer sb = StringBuffer();
    String statusHeader = tiersSaved ? "OFICIAL" : "PRÉVIA";
    sb.writeln("*🎱 NÍVEIS (POTES) - $statusHeader*");
    sb.writeln("*${event.title.toUpperCase()}*");
    sb.writeln("");

    for (int i = 0; i < tiers.length; i++) {
      sb.writeln("*🟢 NÍVEL ${i + 1}*");
      if (tiers[i].isEmpty) {
        sb.writeln("(Vazio)");
      } else {
        for (var p in tiers[i]) {
          String name = p.nickname.isNotEmpty ? p.nickname : p.name;
          sb.writeln("- $name");
        }
      }
      sb.writeln("");
    }
    if (goalkeepers.isNotEmpty) {
      sb.writeln("*🧤 GOLEIROS*");
      for (var p in goalkeepers) {
        String name = p.nickname.isNotEmpty ? p.nickname : p.name;
        sb.writeln("- $name");
      }
      sb.writeln("");
    }
    sb.writeln(
      tiersSaved
          ? "_Definição Oficial dos Níveis_"
          : "_Prévia sujeita a alterações_",
    );
    return sb.toString();
  }

  String generateTeamsText() {
    StringBuffer sb = StringBuffer();
    String statusHeader = teamsSaved ? "OFICIAL" : "PRÉVIA";
    sb.writeln("*⚽ TIMES DEFINIDOS - $statusHeader*");
    sb.writeln("*${event.title.toUpperCase()}*");
    sb.writeln("");

    for (int i = 0; i < generatedTeams.length; i++) {
      sb.writeln("*🛡️ TIME ${i + 1}*");

      final gks = generatedTeams[i]
          .where((p) => p.roleInMatch == 'goalkeeper')
          .toList();
      final slottedLines = getSlottedLinePlayers(
        generatedTeams[i],
      ); // <--- A MÁGICA DOS ESPAÇOS AQUI!

      for (var p in gks) {
        String name = p.nickname.isNotEmpty ? p.nickname : p.name;
        sb.writeln("🧤 $name [GOL]");
      }

      for (int j = 0; j < slottedLines.length; j++) {
        var p = slottedLines[j];
        if (p != null) {
          String name = p.nickname.isNotEmpty ? p.nickname : p.name;
          // No WhatsApp: Se for Oficial (Salvo) mostra a sequência. Se for Prévia, mostra o nível original.
          int displayTier = teamsSaved ? (j + 1) : getPlayerTier(p.uid);
          sb.writeln("- ($displayTier) $name");
        } else {
          sb.writeln(
            "- (${j + 1}) [Vaga Disponível]",
          ); // <-- ESPAÇO EM BRANCO NO WHATSAPP
        }
      }
      sb.writeln("");
    }
    sb.writeln(
      teamsSaved
          ? "_Escalação Oficial_"
          : "_Simulação de Sorteio (Não Oficial)_",
    );
    return sb.toString();
  }

  bool get hasMismatchedParticipants {
    if (!tiersGenerated) return false;

    // 1. Filtra ativos do evento
    final todosAtivos = event.participants
        .where((p) => p.status == 'active')
        .toList();

    // 2. Lógica para Linha (mesma do sorteio)
    final ativosLinha = todosAtivos
        .where((p) => p.roleInMatch != 'goalkeeper')
        .toList();
    final linePlayersLimit = (ativosLinha.length > event.maxLinePlayers)
        ? ativosLinha.sublist(0, event.maxLinePlayers)
        : ativosLinha;

    // 3. Lógica para Goleiros (mesma do sorteio)
    final ativosGks = todosAtivos
        .where((p) => p.roleInMatch == 'goalkeeper')
        .toList();
    final gksLimit = (ativosGks.length > event.maxGoalkeepers)
        ? ativosGks.sublist(0, event.maxGoalkeepers)
        : ativosGks;

    // 4. IDs esperados (Linha + Goleiros se necessário)
    final Set<String> expectedIds = linePlayersLimit.map((p) => p.uid).toSet();
    if (includeGoalkeepers) {
      expectedIds.addAll(gksLimit.map((g) => g.uid));
    }

    // 5. IDs atuais nos Tiers
    final Set<String> currentTierIds = tiers
        .expand((tier) => tier)
        .map((p) => p.uid)
        .toSet();
    if (includeGoalkeepers) {
      currentTierIds.addAll(goalkeepers.map((g) => g.uid));
    }

    // 6. Comparação
    return !expectedIds.containsAll(currentTierIds) ||
        !currentTierIds.containsAll(expectedIds);
  }
}
