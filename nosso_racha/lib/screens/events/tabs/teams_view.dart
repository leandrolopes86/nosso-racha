import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/participant_model.dart';
import '../components/sorting_player_tile.dart';

class TeamsView extends StatelessWidget {
  final List<List<ParticipantModel>> generatedTeams;
  final bool isEditable;
  final bool isGenerated;
  final bool isSaved;

  // Permissões
  final bool canEdit;
  final bool canSort;
  final bool canReopen;

  final bool tiersSaved;
  final int maxPerTeam;
  final bool includeGoalkeepers;
  final List<List<ParticipantModel>> tiers;

  final VoidCallback onSort;
  final VoidCallback onSave;
  final VoidCallback onReopen;
  final Function(ParticipantModel, int) onMovePlayer;
  final Function(int, int) onReorderTeams;
  final Function(bool) onToggleGoalkeepers;
  final Function(ParticipantModel, int, int) onReorderWithinTeam;
  final Function(int) onSortTeam; // <--- NOVO

  // --- FUNÇÃO DE SLOTS INJETADA DO CONTROLLER ---
  final List<ParticipantModel?> Function(List<ParticipantModel>)
      getSlottedLinePlayers;
  final int Function(String) getPlayerTier;

  const TeamsView({
    super.key,
    required this.generatedTeams,
    required this.isEditable,
    required this.isGenerated,
    required this.isSaved,
    required this.canEdit,
    required this.canSort,
    required this.canReopen,
    required this.tiersSaved,
    required this.maxPerTeam,
    required this.includeGoalkeepers,
    required this.tiers,
    required this.onSort,
    required this.onSave,
    required this.onReopen,
    required this.onMovePlayer,
    required this.onReorderTeams,
    required this.onToggleGoalkeepers,
    required this.onReorderWithinTeam,
    required this.onSortTeam, // <--- NOVO
    required this.getSlottedLinePlayers,
    required this.getPlayerTier,
  });

  // --- LÓGICA DO DIÁLOGO DE OPÇÕES DO JOGADOR ---
  void _showMoveTeamDialog(BuildContext context, ParticipantModel player,
      int currentTeamIndex, bool isFirstInGroup, bool isLastInGroup) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            "Mover: ${player.nickname.isNotEmpty ? player.nickname : player.name}"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- OPÇÕES DE REORDENAR DENTRO DO MESMO TIME ---
              if (!isFirstInGroup)
                ListTile(
                  leading: Icon(LucideIcons.arrowUp, color: Colors.green),
                  title: const Text("Subir Posição"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReorderWithinTeam(player, currentTeamIndex, -1);
                  },
                ),
              if (!isLastInGroup)
                ListTile(
                  leading: Icon(LucideIcons.arrowDown, color: Colors.orange),
                  title: const Text("Descer Posição"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReorderWithinTeam(player, currentTeamIndex, 1);
                  },
                ),

              const Divider(),

              // --- OPÇÕES DE MOVER PARA OUTRO TIME ---
              ...List.generate(generatedTeams.length, (i) {
                if (i == currentTeamIndex)
                  return const SizedBox.shrink(); // Esconde o time atual
                return ListTile(
                  leading:
                      Icon(LucideIcons.arrowRightCircle, color: Colors.blue),
                  title: Text("Mover para o TIME ${i + 1}"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onMovePlayer(player, i);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCELAR"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isChristmas = Theme.of(context).cardTheme.color?.value == 0xFF2E7D32;
    final headerColor = isChristmas ? Colors.white : Colors.black87;
    final subColor = isChristmas ? Colors.white70 : Colors.grey;

    final int dynamicLimit = maxPerTeam + (includeGoalkeepers ? 1 : 0);

    // --- TELA VAZIA (ANTES DO SORTEIO) ---
    if (!isGenerated && !isSaved) {
      if (!canEdit && !canSort)
        return const Center(child: Text("Sorteio não realizado."));

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.dices, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Os níveis estão definidos.",
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            if (canSort)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: CheckboxListTile(
                  title: const Text("Incluir Goleiros no Sorteio?",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      "Se marcado, distribui 1 goleiro por time. Se não, sorteia apenas a linha."),
                  value: includeGoalkeepers,
                  activeColor: const Color(0xFF2E7D32),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(LucideIcons.shield, color: Colors.purple),
                  onChanged: (val) => onToggleGoalkeepers(val ?? false),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (tiersSaved && canSort) ? onSort : null,
              icon: Icon(LucideIcons.shuffle),
              label: const Text("REALIZAR SORTEIO AGORA"),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
                backgroundColor: canSort ? null : Colors.grey,
              ),
            ),
            if (!tiersSaved)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: Text("Salve os níveis na aba anterior primeiro.",
                    style: TextStyle(color: Colors.red)),
              )
          ],
        ),
      );
    }

    // --- TELA COM TIMES (LISTA) ---
    return Column(
      children: [
        if (canEdit && isEditable)
          Container(
              padding: const EdgeInsets.all(12),
              color: Colors.amber.withOpacity(0.2),
              child: const Row(children: [
                Icon(LucideIcons.arrowUpDown, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        "Arraste pelo ícone ≡ para mudar a ordem dos times. Clique nas setas azuis para mudar jogadores.",
                        style: TextStyle(fontSize: 12, color: Colors.brown)))
              ])),
        if (!isEditable)
          Container(
              padding: const EdgeInsets.all(12),
              color: Colors.green.withOpacity(0.1),
              child: const Row(children: [
                Icon(LucideIcons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                    child: Text("Times Oficiais.",
                        style: TextStyle(fontSize: 12, color: Colors.green)))
              ])),

        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: generatedTeams.length,
            onReorder: onReorderTeams,
            buildDefaultDragHandles: false,
            itemBuilder: (context, teamIndex) {
              int currentCount = generatedTeams[teamIndex].length;
              bool isOverLimit = currentCount > dynamicLimit;
              final Key itemKey = ObjectKey(generatedTeams[teamIndex]);

              Widget teamCard = Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                color: Theme.of(context).cardTheme.color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: (isEditable && isOverLimit)
                        ? const BorderSide(color: Colors.red, width: 2)
                        : BorderSide.none),
                child: Column(
                  children: [
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                            color: (isEditable && isOverLimit)
                                ? Colors.red.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12))),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  if (isEditable)
                                    ReorderableDragStartListener(
                                      index: teamIndex,
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 8.0),
                                        child: Icon(Icons.drag_handle,
                                            color: Colors.grey),
                                      ),
                                    ),
                                  Text("TIME ${teamIndex + 1}",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: (isEditable && isOverLimit)
                                              ? Colors.red
                                              : headerColor)),

                                  // --- NOVO: BOTÃO DE ORDENAÇÃO RÁPIDA ---
                                  if (isEditable)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Tooltip(
                                        message: "Ordenar pelo Nível Original",
                                        child: InkWell(
                                          onTap: () => onSortTeam(teamIndex),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4.0),
                                            child: Icon(LucideIcons.listOrdered,
                                                size: 18, color: Colors.blue),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text("$currentCount / $dynamicLimit",
                                  style: TextStyle(
                                      color: (isEditable && isOverLimit)
                                          ? Colors.red
                                          : subColor,
                                      fontWeight: FontWeight.bold))
                            ])),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Builder(builder: (context) {
                        final gks = generatedTeams[teamIndex]
                            .where((p) => p.roleInMatch == 'goalkeeper')
                            .toList();

                        // Aplica a lógica inteligente de Slots (Vagas)
                        final slottedLines =
                            getSlottedLinePlayers(generatedTeams[teamIndex]);

                        // A lista original 'lines' é necessária para saber o índice real e permitir Subir/Descer
                        final linesArray = generatedTeams[teamIndex]
                            .where((p) => p.roleInMatch != 'goalkeeper')
                            .toList();

                        List<Widget> playerTiles = [];

                        // Monta Goleiros
                        for (int i = 0; i < gks.length; i++) {
                          final p = gks[i];
                          playerTiles.add(SortingPlayerTile(
                            player: p,
                            isEditable: isEditable,
                            isTeamView: true,
                            tier: 0,
                            onOptionsTap: isEditable
                                ? () => _showMoveTeamDialog(context, p,
                                    teamIndex, i == 0, i == gks.length - 1)
                                : null,
                          ));
                        }

                        // Monta Jogadores de Linha com Vagas (Slots)
                        for (int i = 0; i < slottedLines.length; i++) {
                          final p = slottedLines[i];

                          if (p != null) {
                            // Verifica o índice dele na array crua para habilitar botões de subir/descer
                            int realIndex = linesArray.indexOf(p);

                            // Nível visual: Se editando, mostra o nível original do atleta. Se salvo, mostra a posição real (1, 2, 3...)
                            int displayTier =
                                isEditable ? getPlayerTier(p.uid) : (i + 1);

                            playerTiles.add(SortingPlayerTile(
                              player: p,
                              isEditable: isEditable,
                              isTeamView: true,
                              tier: displayTier,
                              onOptionsTap: isEditable
                                  ? () => _showMoveTeamDialog(
                                      context,
                                      p,
                                      teamIndex,
                                      realIndex == 0,
                                      realIndex == linesArray.length - 1)
                                  : null,
                            ));
                          } else {
                            // --- ESPAÇO VAZIO (VAGA DISPONÍVEL) ---
                            playerTiles.add(Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isChristmas
                                    ? Colors.white10
                                    : Colors.grey.withOpacity(0.05),
                                border: Border.all(
                                    color: Colors.grey.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.userMinus,
                                      size: 16,
                                      color: Colors.grey.withOpacity(0.7)),
                                  const SizedBox(width: 8),
                                  Text("(${i + 1})",
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text("Vaga Disponível",
                                        style: TextStyle(
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic)),
                                  ),
                                ],
                              ),
                            ));
                          }
                        }

                        return Column(children: playerTiles);
                      }),
                    ),
                  ],
                ),
              );

              if (isEditable) {
                return DragTarget<ParticipantModel>(
                  key: itemKey,
                  onAccept: (player) {
                    // --- CORREÇÃO DO BUG: SÓ ACEITA SE FOR DE UM TIME DIFERENTE ---
                    bool isAlreadyInTeam = generatedTeams[teamIndex]
                        .any((p) => p.uid == player.uid);
                    if (!isAlreadyInTeam) {
                      onMovePlayer(player, teamIndex);
                    }
                  },
                  builder: (context, candidateData, rejectedData) =>
                      candidateData.isNotEmpty
                          ? Opacity(opacity: 0.7, child: teamCard)
                          : teamCard,
                );
              }
              return KeyedSubtree(key: itemKey, child: teamCard);
            },
          ),
        ),

        // --- RODAPÉ DE AÇÃO ---
        if (canEdit || canReopen || !isSaved)
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: isSaved
                  ? OutlinedButton.icon(
                      onPressed: canReopen ? onReopen : null,
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: canReopen ? Colors.red : Colors.grey),
                          foregroundColor:
                              canReopen ? Colors.red : Colors.grey),
                      icon: Icon(LucideIcons.rotateCcw),
                      label: const Text("REABRIR SORTEIO (EDITAR)"),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (tiersSaved && canSort) ? onSort : null,
                            icon: Icon(LucideIcons.shuffle),
                            label: const Text("SORTEAR"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (tiersSaved && canSort) ? onSave : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    canSort ? Colors.black87 : Colors.grey),
                            icon: Icon(LucideIcons.save),
                            label: const Text("SALVAR TIMES"),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
