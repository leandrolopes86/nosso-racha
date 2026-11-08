import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/participant_model.dart';
import 'team_name_display.dart';

class TeamScoreControl extends StatelessWidget {
  final String teamName;
  final int score;
  final Function(int) onChanged;
  final CrossAxisAlignment alignment;
  final bool enabled;

  // Dados para o TeamNameDisplay
  final Map<String, List<ParticipantModel>> teamsMap;
  final List<String> tier1PlayerIds;

  const TeamScoreControl({
    super.key,
    required this.teamName,
    required this.score,
    required this.onChanged,
    required this.teamsMap,
    required this.tier1PlayerIds,
    this.alignment = CrossAxisAlignment.center,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        TeamNameDisplay(
          teamName: teamName,
          teamsMap: teamsMap,
          tier1PlayerIds: tier1PlayerIds,
          alignment: alignment,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
                onPressed:
                    (enabled && score > 0) ? () => onChanged(score - 1) : null,
                icon: Icon(LucideIcons.minus, size: 16),
                style: IconButton.styleFrom(minimumSize: const Size(32, 32))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text("$score",
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold))),
            IconButton.filled(
                onPressed: enabled ? () => onChanged(score + 1) : null,
                icon: Icon(LucideIcons.plus, size: 16),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(32, 32))),
          ],
        )
      ],
    );
  }
}
