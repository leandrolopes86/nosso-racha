import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/match_model.dart';
import '../../../models/participant_model.dart';

class ScorersEditor extends StatefulWidget {
  final MatchModel match;
  final Map<String, List<ParticipantModel>> teamsMap;
  final Function(Map<String, int>, Map<String, int>) onSave;

  const ScorersEditor(
      {super.key,
      required this.match,
      required this.teamsMap,
      required this.onSave});

  @override
  State<ScorersEditor> createState() => _ScorersEditorState();
}

class _ScorersEditorState extends State<ScorersEditor> {
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
                // Só permite adicionar se o total ainda não atingiu os gols do time
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
