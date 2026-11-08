import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/participant_model.dart';

class TeamNameDisplay extends StatelessWidget {
  final String teamName;
  final Map<String, List<ParticipantModel>> teamsMap;
  final List<String> tier1PlayerIds;
  final CrossAxisAlignment alignment;
  final TextStyle? style;
  final bool isLoadingTeams;

  const TeamNameDisplay({
    super.key,
    required this.teamName,
    required this.teamsMap,
    required this.tier1PlayerIds,
    this.alignment = CrossAxisAlignment.start,
    this.style,
    this.isLoadingTeams = false,
  });

  String _getTier1Name() {
    if (isLoadingTeams || teamsMap[teamName] == null) return "";
    try {
      final players = teamsMap[teamName]!;
      final p = players.firstWhere((u) => tier1PlayerIds.contains(u.uid),
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

  void _showTeamDetails(BuildContext context) {
    final players = teamsMap[teamName] ?? [];

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
                          final isTier1 = tier1PlayerIds.contains(p.uid);
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
                    child: const Text("FECHAR")),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final tier1Name = _getTier1Name();

    TextAlign textAlign;
    if (alignment == CrossAxisAlignment.center) {
      textAlign = TextAlign.center;
    } else if (alignment == CrossAxisAlignment.end)
      textAlign = TextAlign.end;
    else
      textAlign = TextAlign.start;

    return InkWell(
      onTap: () => _showTeamDetails(context),
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(teamName,
              style: style ?? const TextStyle(fontWeight: FontWeight.bold),
              textAlign: textAlign,
              overflow: TextOverflow.ellipsis),
          if (tier1Name.isNotEmpty)
            Text("($tier1Name)",
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                textAlign: textAlign,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
