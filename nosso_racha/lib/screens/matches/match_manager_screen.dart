import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/event_model.dart';
import '../../models/match_model.dart';
import '../../models/participant_model.dart';
import '../../services/match_service.dart';
import '../../services/auth_service.dart';
// Importação dos Componentes
import 'components/team_name_display.dart';
import 'components/team_score_control.dart';
import 'components/ranking_sheet.dart';

class MatchManagerScreen extends StatefulWidget {
  final EventModel event;

  const MatchManagerScreen({super.key, required this.event});

  @override
  State<MatchManagerScreen> createState() => _MatchManagerScreenState();
}

class _MatchManagerScreenState extends State<MatchManagerScreen> {
  bool _isInit = true;

  // Cache de dados para os componentes
  final Map<String, List<ParticipantModel>> _teamsMap = {};
  List<String> _tier1PlayerIds = [];
  bool _isLoadingTeams = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final matchService = Provider.of<MatchService>(context, listen: false);
      matchService.initializeQueueIfNotExists(widget.event);
      _loadTeamData();
      _isInit = false;
    }
  }

  Future<void> _loadTeamData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data['tiers_distribution'] != null &&
            data['tiers_distribution'] is Map) {
          final tiersMap =
              Map<String, dynamic>.from(data['tiers_distribution']);
          final sortedKeys = tiersMap.keys.toList()..sort();
          if (sortedKeys.isNotEmpty) {
            final tier1List = List.from(tiersMap[sortedKeys[0]] ?? []);
            _tier1PlayerIds =
                tier1List.map((x) => ParticipantModel.fromMap(x).uid).toList();
          }
        }
        if (data['teams_distribution'] != null &&
            data['teams_distribution'] is Map) {
          final teamsMapRaw =
              Map<String, dynamic>.from(data['teams_distribution']);
          teamsMapRaw.forEach((key, value) {
            if (value is List) {
              _teamsMap[key] =
                  value.map((x) => ParticipantModel.fromMap(x)).toList();
            }
          });
        }
      }
    } catch (e) {
      print("Erro ao carregar dados dos times: $e");
    } finally {
      if (mounted) setState(() => _isLoadingTeams = false);
    }
  }

  // --- ACTIONS & DIALOGS ---

  String _getTier1Name(String teamName) {
    if (_isLoadingTeams || _teamsMap[teamName] == null) return "";
    try {
      final players = _teamsMap[teamName]!;
      final p = players.firstWhere((u) => _tier1PlayerIds.contains(u.uid),
          orElse: () => ParticipantModel(
              uid: '', name: '', status: '', registeredAt: DateTime.now()));
      if (p.uid.isNotEmpty) {
        return p.nickname.isNotEmpty ? p.nickname : p.name;
      }
      return "";
    } catch (e) {
      return "";
    }
  }

  void _showTeamDetails(String teamName) {
    final players = _teamsMap[teamName] ?? [];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(LucideIcons.shirt, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(teamName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: players.isEmpty
                    ? const Text("Sem jogadores definidos.")
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: players.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final p = players[index];
                          final isTier1 = _tier1PlayerIds.contains(p.uid);
                          final isGK = p.roleInMatch == 'goalkeeper';
                          final String displayName =
                              p.nickname.isNotEmpty ? p.nickname : p.name;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isGK ? LucideIcons.shield : LucideIcons.user,
                              size: 18,
                              color: isGK ? Colors.purple : Colors.grey,
                            ),
                            title: Text(displayName,
                                style: TextStyle(
                                    fontWeight: isTier1
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            trailing: isTier1
                                ? Icon(LucideIcons.star,
                                    size: 16, color: Colors.amber)
                                : null,
                          );
                        }),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("FECHAR"))
              ],
            ));
  }

  void _showLockedAlert(String reason) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Ação Bloqueada"),
              content: Text(reason, style: const TextStyle(color: Colors.red)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("ENTENDI"))
              ],
            ));
  }

  void _finishMatch(MatchModel match, List<String> queue) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    // CORREÇÃO: Agora usa a permissão de placar ao vivo (ou Master)
    bool canUpdateLiveScore = user != null &&
        (user.isMaster || (user.permissions['can_update_live_score'] ?? false));

    if (!canUpdateLiveScore) {
      _showLockedAlert("Você não tem permissão para finalizar jogos.");
      return;
    }

    if (match.goalsA == match.goalsB) {
      // EMPATE
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Empate! Definir Prioridade"),
          content: const Text(
              "Ambos os times saem.\nQuem ganhou o sorteio/par-ou-ímpar para ser o próximo da fila?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processFinish(match, queue, match.teamAName);
              },
              child: Text(match.teamAName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processFinish(match, queue, match.teamBName);
              },
              child: Text(match.teamBName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      // VITÓRIA
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Encerrar Partida"),
          content: Text(
              "Confirmar vitória do ${match.goalsA > match.goalsB ? match.teamAName : match.teamBName}?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCELAR")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _processFinish(match, queue, null);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("CONFIRMAR"),
            ),
          ],
        ),
      );
    }
  }

  void _processFinish(
      MatchModel match, List<String> queue, String? winnerPriority) {
    Provider.of<MatchService>(context, listen: false)
        .finishMatch(widget.event.id!, match, queue, winnerPriority);
  }

  void _confirmRevertMatch(MatchModel match) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null || !user.canRevertMatch) {
      _showLockedAlert("Você não tem permissão para reverter jogos.");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Corrigir Último Jogo"),
        content: const Text(
          "Deseja trazer este jogo de volta para o campo?\n\n"
          "Isso restaurará a fila EXATAMENTE como estava durante este jogo.\n"
          "O jogo atual em andamento será descartado.",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCELAR")),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _revertLastMatchToCurrent(match);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            icon: Icon(LucideIcons.undo2, size: 16),
            label: const Text("REVERTER JOGO"),
          ),
        ],
      ),
    );
  }

  Future<void> _revertLastMatchToCurrent(MatchModel match) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final eventRef = firestore.collection('events').doc(widget.event.id);

      await firestore.runTransaction((transaction) async {
        final matchRef = eventRef.collection('matches').doc(match.id);
        transaction.delete(matchRef);

        match.isFinished = false;
        match.winnerName = null;

        List<String> restoredQueue = [];
        if (match.queueSnapshot.isNotEmpty) {
          restoredQueue = List.from(match.queueSnapshot);
        } else {
          final snapshot = await transaction.get(eventRef);
          final data = snapshot.data() as Map<String, dynamic>;
          restoredQueue = List<String>.from(data['match_queue'] ?? []);
          if (!restoredQueue.contains(match.teamAName))
            restoredQueue.insert(0, match.teamAName);
          if (!restoredQueue.contains(match.teamBName))
            restoredQueue.insert(1, match.teamBName);
        }

        transaction.update(eventRef, {
          'current_match_data': match.toMap(),
          'match_queue': restoredQueue,
        });
      });

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Jogo restaurado com sucesso!"),
            backgroundColor: Colors.orange));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao reverter: $e"),
            backgroundColor: Colors.red));
    }
  }

  // --- ARTILHARIA (LIVE) ---
  void _editLiveMatchScorers(MatchModel match) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    // VERIFICAÇÃO DA NOVA PERMISSÃO
    bool canUpdateLiveScore = user != null &&
        (user.isMaster || (user.permissions['can_update_live_score'] ?? false));

    if (!canUpdateLiveScore) {
      _showLockedAlert(
          "Você não tem permissão para editar artilharia ao vivo.");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ScorersEditor(
        match: match,
        teamsMap: _teamsMap,
        onSave: (scorersA, scorersB) async {
          try {
            await FirebaseFirestore.instance
                .collection('events')
                .doc(widget.event.id)
                .update({
              'current_match_data.scorers_a': scorersA,
              'current_match_data.scorers_b': scorersB,
            });
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Artilharia atualizada!"),
                  backgroundColor: Colors.green));
          } catch (e) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Erro ao salvar: $e"),
                  backgroundColor: Colors.red));
          }
        },
      ),
    );
  }

  // --- ARTILHARIA (GOLS DA PARTIDA - HISTÓRICO) ---
  void _handleScoreClick(MatchModel match, bool canEdit) {
    if (match.goalsA == 0 && match.goalsB == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Partida sem gols (0x0).")));
      return;
    }
    bool hasScorers = match.scorersA.isNotEmpty || match.scorersB.isNotEmpty;

    if (hasScorers) {
      _showScorersView(match, canEdit);
    } else {
      if (canEdit) {
        _showScorersEditor(match);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Autores dos gols não informados.")));
      }
    }
  }

  void _showScorersView(MatchModel match, bool canEdit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Gols da Partida",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (canEdit)
                    TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showScorersEditor(match);
                        },
                        icon: Icon(LucideIcons.pencil, size: 16),
                        label: const Text("EDITAR"))
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _buildScorerListForTeam(
                      match.teamAName, match.scorersA, Colors.blue),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildScorerListForTeam(
                      match.teamBName, match.scorersB, Colors.green),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScorersEditor(MatchModel match) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ScorersEditor(
        match: match,
        teamsMap: _teamsMap,
        onSave: (scorersA, scorersB) async {
          try {
            await FirebaseFirestore.instance
                .collection('events')
                .doc(widget.event.id)
                .collection('matches')
                .doc(match.id)
                .update({
              'scorers_a': scorersA,
              'scorers_b': scorersB,
            });
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Artilharia salva!"),
                  backgroundColor: Colors.green));
          } catch (e) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("Erro ao salvar: $e"),
                  backgroundColor: Colors.red));
          }
        },
      ),
    );
  }

  Widget _buildScorerListForTeam(
      String teamName, Map<String, int> scorers, Color color) {
    if (scorers.isEmpty) return const SizedBox.shrink();
    List<Widget> rows = [];
    scorers.forEach((uid, goals) {
      if (goals > 0) {
        final players = _teamsMap[teamName] ?? [];
        final p = players.firstWhere((p) => p.uid == uid,
            orElse: () => ParticipantModel(
                uid: '',
                name: 'Desconhecido',
                status: '',
                registeredAt: DateTime.now()));
        String name = p.nickname.isNotEmpty ? p.nickname : p.name;
        rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(children: [
              Icon(LucideIcons.goal, size: 16, color: color),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (goals > 1)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text("$goals gols",
                        style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.bold)))
            ])));
      }
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(teamName,
          style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...rows
    ]);
  }

  // --- CANCELAR/LIMPAR JOGO ATUAL ---
  void _cancelCurrentMatch() {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;

    // CORREÇÃO: Usa permissão de placar ou master para cancelar
    bool canUpdateLiveScore = user != null &&
        (user.isMaster || (user.permissions['can_update_live_score'] ?? false));
    if (!canUpdateLiveScore) return;

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Cancelar Jogo Atual?"),
              content: const Text(
                  "Isso removerá o jogo do campo sem salvar no histórico. Os times permanecerão na fila.\n\nUse isso se o jogo foi criado por engano."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("VOLTAR")),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await FirebaseFirestore.instance
                        .collection('events')
                        .doc(widget.event.id)
                        .update({'current_match_data': null});
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white),
                  child: const Text("CANCELAR JOGO"),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final matchService = Provider.of<MatchService>(context);
    final currentUser = Provider.of<AuthService>(context).currentUser;

    final isStaff = currentUser != null && currentUser.isStaff;
    final canRevert = currentUser != null && currentUser.canRevertMatch;

    // PERMISSÃO: Placares, Gols, Finalizar e Cancelar
    final bool canUpdateLiveScore = currentUser != null &&
        (currentUser.isMaster ||
            (currentUser.permissions['can_update_live_score'] ?? false));

    // Permissão para editar placar no histórico (geralmente Staff/Master)
    final bool canEditHistoryScore = isStaff;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Sequência de Jogos"),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.trophy),
            tooltip: "Classificação",
            onPressed: () => RankingSheet.show(
                context, widget.event.id!, _teamsMap, _tier1PlayerIds),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: matchService.getEventQueueStream(widget.event.id!),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final queueList = List<String>.from(data['match_queue'] ?? []);
          final currentMatchData = data['current_match_data'];

          MatchModel? currentMatch;
          if (currentMatchData != null) {
            currentMatch = MatchModel.fromMap('current', currentMatchData);
          }

          return Column(
            children: [
              // --- PLACAR E JOGO ATUAL ---
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).cardColor,
                child: Column(
                  children: [
                    const Text("EM CAMPO",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.grey)),
                    const SizedBox(height: 16),
                    if (currentMatch != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                              child: TeamScoreControl(
                            teamName: currentMatch.teamAName,
                            score: currentMatch.goalsA,
                            // Protegido por permissão
                            onChanged: (val) {
                              if (!canUpdateLiveScore) return;
                              matchService.updateScore(
                                  widget.event.id!, val, currentMatch!.goalsB);
                            },
                            alignment: CrossAxisAlignment.end,
                            enabled:
                                canUpdateLiveScore, // <--- Controla botões +/-
                            teamsMap: _teamsMap,
                            tier1PlayerIds: _tier1PlayerIds,
                          )),
                          const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12.0),
                              child: Text("X",
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey))),
                          Expanded(
                              child: TeamScoreControl(
                            teamName: currentMatch.teamBName,
                            score: currentMatch.goalsB,
                            // Protegido por permissão
                            onChanged: (val) {
                              if (!canUpdateLiveScore) return;
                              matchService.updateScore(
                                  widget.event.id!, currentMatch!.goalsA, val);
                            },
                            alignment: CrossAxisAlignment.start,
                            enabled:
                                canUpdateLiveScore, // <--- Controla botões +/-
                            teamsMap: _teamsMap,
                            tier1PlayerIds: _tier1PlayerIds,
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // BOTÃO ARTILHARIA
                      if (canUpdateLiveScore)
                        OutlinedButton.icon(
                          onPressed: () => _editLiveMatchScorers(currentMatch!),
                          icon: Icon(LucideIcons.goal, size: 16),
                          label: const Text("ARTILHARIA / GOLS"),
                          style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                        ),
                      const SizedBox(height: 16),

                      // CORREÇÃO: Visibilidade controlada pela nova permissão
                      if (canUpdateLiveScore)
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _finishMatch(currentMatch!, queueList),
                                icon: Icon(LucideIcons.flag),
                                label: const Text("FINALIZAR JOGO"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(16)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _cancelCurrentMatch,
                              icon: Icon(LucideIcons.trash2,
                                  size: 16, color: Colors.red),
                              label: const Text("CANCELAR JOGO (Erro)",
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12)),
                            )
                          ],
                        ),
                    ] else
                      // --- ESTADO SEM JOGO (Controle Manual) ---
                      Column(
                        children: [
                          const Text("Nenhum jogo em andamento.",
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          if (queueList.length >= 2 && isStaff)
                            ElevatedButton.icon(
                              onPressed: () => Provider.of<MatchService>(
                                      context,
                                      listen: false)
                                  .startNextMatch(widget.event.id!, queueList),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 16)),
                              icon: Icon(LucideIcons.play),
                              label: const Text("INICIAR PRÓXIMO JOGO"),
                            )
                          else if (queueList.length < 2)
                            const Text("Aguardando mais times...",
                                style: TextStyle(color: Colors.orange)),
                        ],
                      ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // --- PRÓXIMOS NA FILA ---
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(children: [
                            Icon(LucideIcons.listOrdered, size: 18),
                            const SizedBox(width: 8),
                            Text(
                                "Próximos (${queueList.length > 2 ? queueList.length - 2 : 0})",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))
                          ])),

                      if (queueList.length > 2)
                        Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: queueList.length - 2,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final teamName = queueList[index + 2];
                              return ActionChip(
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(teamName),
                                    Text(_getTier1Name(teamName),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54)),
                                  ],
                                ),
                                backgroundColor: Colors.orange[50],
                                side: const BorderSide(color: Colors.orange),
                                onPressed: () => _showTeamDetails(teamName),
                              );
                            },
                          ),
                        )
                      else
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text("Sem times na espera.",
                                style: TextStyle(color: Colors.grey))),

                      const Divider(),

                      // --- HISTÓRICO ---
                      const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(children: [
                            Icon(LucideIcons.history, size: 18),
                            SizedBox(width: 8),
                            Text("Histórico",
                                style: TextStyle(fontWeight: FontWeight.bold))
                          ])),

                      StreamBuilder<QuerySnapshot>(
                        stream: matchService
                            .getMatchesHistoryStream(widget.event.id!),
                        builder: (context, snapHistory) {
                          if (!snapHistory.hasData)
                            return const SizedBox.shrink();
                          final matches = snapHistory.data!.docs
                              .map((d) => MatchModel.fromMap(
                                  d.id, d.data() as Map<String, dynamic>))
                              .toList();
                          if (matches.isEmpty)
                            return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text("Nenhum jogo finalizado."));

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final m = matches[index];
                              bool isDraw = m.goalsA == m.goalsB;
                              bool isLastMatch = index == 0;

                              // --- LAYOUT CUSTOMIZADO DO HISTÓRICO ---
                              return InkWell(
                                onTap: () =>
                                    _handleScoreClick(m, canEditHistoryScore),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 16),
                                  decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Colors.grey
                                                  .withOpacity(0.1)))),
                                  child: Row(
                                    children: [
                                      // 1. ID e Status
                                      SizedBox(
                                        width: 45,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text("#${matches.length - index}",
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12)),
                                            if (isDraw)
                                              const Text("E",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.orange,
                                                      fontSize: 12)),
                                          ],
                                        ),
                                      ),

                                      // 2. Conteúdo Central (Times e Placar)
                                      Expanded(
                                        child: Row(
                                          children: [
                                            // Time A
                                            Expanded(
                                                child: TeamNameDisplay(
                                              teamName: m.teamAName,
                                              teamsMap: _teamsMap,
                                              tier1PlayerIds: _tier1PlayerIds,
                                              alignment: CrossAxisAlignment.end,
                                              style: TextStyle(
                                                  fontWeight: m.winnerName ==
                                                          m.teamAName
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: m.winnerName ==
                                                          m.teamAName
                                                      ? Colors.green
                                                      : null,
                                                  fontSize: 14),
                                            )),

                                            // Placar
                                            Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                  color: Colors.grey[200],
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                              child: Text(
                                                  "${m.goalsA} x ${m.goalsB}",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                      fontSize: 16)),
                                            ),

                                            // Time B
                                            Expanded(
                                                child: TeamNameDisplay(
                                              teamName: m.teamBName,
                                              teamsMap: _teamsMap,
                                              tier1PlayerIds: _tier1PlayerIds,
                                              alignment:
                                                  CrossAxisAlignment.start,
                                              style: TextStyle(
                                                  fontWeight: m.winnerName ==
                                                          m.teamBName
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: m.winnerName ==
                                                          m.teamBName
                                                      ? Colors.green
                                                      : null,
                                                  fontSize: 14),
                                            )),
                                          ],
                                        ),
                                      ),

                                      // 3. Ações
                                      SizedBox(
                                        width: 45,
                                        child: (isLastMatch && canRevert)
                                            ? IconButton(
                                                icon: const Icon(
                                                    LucideIcons.undo2,
                                                    size: 20,
                                                    color: Colors.orange),
                                                tooltip: "Reverter Jogo",
                                                padding: EdgeInsets.zero,
                                                alignment:
                                                    Alignment.centerRight,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () =>
                                                    _confirmRevertMatch(m),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ... _ScorersEditor class (mantida igual) ...
class _ScorersEditor extends StatefulWidget {
  final MatchModel match;
  final Map<String, List<ParticipantModel>> teamsMap;
  final Function(Map<String, int>, Map<String, int>) onSave;

  const _ScorersEditor(
      {required this.match, required this.teamsMap, required this.onSave});

  @override
  State<_ScorersEditor> createState() => _ScorersEditorState();
}

class _ScorersEditorState extends State<_ScorersEditor> {
  late Map<String, int> _scorersA;
  late Map<String, int> _scorersB;

  @override
  void initState() {
    super.initState();
    _scorersA = Map.from(widget.match.scorersA);
    _scorersB = Map.from(widget.match.scorersB);
  }

  void _increment(Map<String, int> scorers, String uid, int maxGoals) {
    int currentTotal = scorers.values.fold(0, (sum, val) => sum + val);
    if (currentTotal < maxGoals) {
      setState(() {
        scorers[uid] = (scorers[uid] ?? 0) + 1;
      });
    }
  }

  void _decrement(Map<String, int> scorers, String uid) {
    if ((scorers[uid] ?? 0) > 0) {
      setState(() {
        scorers[uid] = (scorers[uid]!) - 1;
        if (scorers[uid] == 0) scorers.remove(uid);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalA = _scorersA.values.fold(0, (sum, val) => sum + val);
    int totalB = _scorersB.values.fold(0, (sum, val) => sum + val);

    return AlertDialog(
      title: const Text("Informar Gols"),
      content: SizedBox(
        width: double.maxFinite,
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                labelColor: Theme.of(context).primaryColor,
                tabs: [
                  Tab(
                      text:
                          "${widget.match.teamAName} ($totalA/${widget.match.goalsA})"),
                  Tab(
                      text:
                          "${widget.match.teamBName} ($totalB/${widget.match.goalsB})"),
                ],
              ),
              SizedBox(
                height: 300,
                child: TabBarView(
                  children: [
                    _buildPlayerList(
                        widget.match.teamAName, _scorersA, widget.match.goalsA),
                    _buildPlayerList(
                        widget.match.teamBName, _scorersB, widget.match.goalsB),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR")),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_scorersA, _scorersB);
            Navigator.pop(context);
          },
          child: const Text("SALVAR"),
        ),
      ],
    );
  }

  Widget _buildPlayerList(
      String teamName, Map<String, int> scorers, int maxGoals) {
    final players = widget.teamsMap[teamName] ?? [];
    if (players.isEmpty) return const Center(child: Text("Sem jogadores."));

    return ListView.builder(
      itemCount: players.length,
      itemBuilder: (context, index) {
        final p = players[index];
        final count = scorers[p.uid] ?? 0;
        final isGK = p.roleInMatch == 'goalkeeper';

        return ListTile(
          dense: true,
          leading: Icon(isGK ? LucideIcons.shield : LucideIcons.user,
              size: 18, color: Colors.grey),
          title: Text(p.nickname.isNotEmpty ? p.nickname : p.name,
              style: const TextStyle(fontSize: 14)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(LucideIcons.minus, size: 16),
                onPressed: count > 0 ? () => _decrement(scorers, p.uid) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Container(
                width: 30,
                alignment: Alignment.center,
                child: Text("$count",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: Icon(LucideIcons.plus, size: 16, color: Colors.green),
                onPressed: (scorers.values.fold(0, (s, v) => s + v) < maxGoals)
                    ? () => _increment(scorers, p.uid, maxGoals)
                    : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }
}
