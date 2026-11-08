import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/match_model.dart';
import '../../../models/participant_model.dart';
import 'team_name_display.dart';

class RankingSheet {
  static Future<void> show(
    BuildContext context,
    String eventId,
    Map<String, List<ParticipantModel>> teamsMap,
    List<String> tier1PlayerIds,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .collection('matches')
          .where('is_finished', isEqualTo: true)
          .get();

      final matches =
          snapshot.docs.map((d) => MatchModel.fromMap(d.id, d.data())).toList();

      // --- CÁLCULO ESTATÍSTICAS TIMES ---
      Map<String, _TeamStats> teamStats = {};

      // --- CÁLCULO ESTATÍSTICAS JOGADORES (GOLS) ---
      Map<String, int> playerGoals = {};

      for (var match in matches) {
        // 1. Times
        teamStats.putIfAbsent(
            match.teamAName, () => _TeamStats(match.teamAName));
        teamStats.putIfAbsent(
            match.teamBName, () => _TeamStats(match.teamBName));

        final tA = teamStats[match.teamAName]!;
        final tB = teamStats[match.teamBName]!;

        tA.goalsFor += match.goalsA;
        tA.goalsAgainst += match.goalsB;
        tB.goalsFor += match.goalsB;
        tB.goalsAgainst += match.goalsA;

        tA.matchesPlayed++;
        tB.matchesPlayed++;

        if (match.goalsA > match.goalsB) {
          tA.wins++;
        } else if (match.goalsB > match.goalsA) tB.wins++;

        // 2. Jogadores (Artilharia)
        match.scorersA.forEach((uid, goals) {
          playerGoals[uid] = (playerGoals[uid] ?? 0) + goals;
        });
        match.scorersB.forEach((uid, goals) {
          playerGoals[uid] = (playerGoals[uid] ?? 0) + goals;
        });
      }

      // Ordenação Times
      List<_TeamStats> sortedTeams = teamStats.values.toList();
      sortedTeams.sort((a, b) {
        if (b.wins != a.wins) return b.wins.compareTo(a.wins);
        if (b.goalDifference != a.goalDifference)
          return b.goalDifference.compareTo(a.goalDifference);
        return b.goalsFor.compareTo(a.goalsFor);
      });

      // Ordenação Artilheiros
      List<MapEntry<String, int>> sortedScorers = playerGoals.entries.toList();
      sortedScorers
          .sort((a, b) => b.value.compareTo(a.value)); // Maior para menor

      if (!context.mounted) return;

      // Flatten para buscar nomes dos jogadores rapidamente
      Map<String, ParticipantModel> allPlayersMap = {};
      for (var list in teamsMap.values) {
        for (var p in list) {
          allPlayersMap[p.uid] = p;
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => FractionallySizedBox(
          heightFactor: 0.85, // Altura maior para caber as abas
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text("Estatísticas do Racha",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                TabBar(
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Theme.of(context).primaryColor,
                  tabs: const [
                    Tab(text: "Classificação", icon: Icon(LucideIcons.trophy)),
                    Tab(text: "Artilharia", icon: Icon(LucideIcons.goal)),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [
                      // ABA 1: Classificação dos Times
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: DataTable(
                          columnSpacing: 12,
                          horizontalMargin: 8,
                          dataRowMinHeight: 48,
                          columns: const [
                            DataColumn(label: Text("#")),
                            DataColumn(label: Text("Time")),
                            DataColumn(label: Text("V"), tooltip: "Vitórias"),
                            DataColumn(label: Text("SG"), tooltip: "Saldo"),
                            DataColumn(label: Text("GP"), tooltip: "Gols Pró"),
                          ],
                          rows: List<DataRow>.generate(sortedTeams.length,
                              (index) {
                            final s = sortedTeams[index];

                            // Lógica de empate para Times: Mesmo Rank se V, SG e GP forem iguais
                            int rank = sortedTeams.indexWhere((t) =>
                                    t.wins == s.wins &&
                                    t.goalDifference == s.goalDifference &&
                                    t.goalsFor == s.goalsFor) +
                                1;

                            final isLeader = rank == 1;
                            final style = TextStyle(
                                fontWeight: isLeader
                                    ? FontWeight.bold
                                    : FontWeight.normal);

                            return DataRow(
                              color: isLeader
                                  ? WidgetStateProperty.all(
                                      Colors.green.withOpacity(0.1))
                                  : null,
                              cells: [
                                DataCell(Text("$rankº", style: style)),
                                DataCell(TeamNameDisplay(
                                    teamName: s.name,
                                    teamsMap: teamsMap,
                                    tier1PlayerIds: tier1PlayerIds,
                                    style: style)),
                                DataCell(Text("${s.wins}", style: style)),
                                DataCell(
                                    Text("${s.goalDifference}", style: style)),
                                DataCell(Text("${s.goalsFor}", style: style)),
                              ],
                            );
                          }),
                        ),
                      ),

                      // ABA 2: Artilharia
                      sortedScorers.isEmpty
                          ? const Center(
                              child: Text("Nenhum gol marcado ainda."))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: sortedScorers.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final entry = sortedScorers[index];
                                final p = allPlayersMap[entry.key];
                                final name = p != null
                                    ? (p.nickname.isNotEmpty
                                        ? p.nickname
                                        : p.name)
                                    : "Desconhecido";
                                final goals = entry.value;

                                // Lógica de empate para Artilharia: Mesmo Rank se Gols forem iguais
                                // Procura o primeiro índice na lista que tem essa quantidade de gols
                                int rank = sortedScorers
                                        .indexWhere((e) => e.value == goals) +
                                    1;

                                final isTop = rank == 1;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        isTop ? Colors.amber : Colors.grey[200],
                                    foregroundColor:
                                        isTop ? Colors.white : Colors.black87,
                                    child:
                                        Text("$rank"), // Exibe 1, 1, 3, 3, 5...
                                  ),
                                  title: Text(name,
                                      style: TextStyle(
                                          fontWeight: isTop
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: Text("$goals gols",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green)),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erro ao gerar ranking: $e")));
    }
  }
}

class _TeamStats {
  String name;
  int wins = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int matchesPlayed = 0;
  int get goalDifference => goalsFor - goalsAgainst;
  _TeamStats(this.name);
}
