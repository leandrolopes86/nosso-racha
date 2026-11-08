import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/participant_model.dart';
import '../components/sorting_player_tile.dart';

class TiersView extends StatelessWidget {
  final List<List<ParticipantModel>> tiers;
  final List<ParticipantModel> goalkeepers;
  final bool isEditable;
  final bool isSaved;

  // Permissões
  final bool canEdit; // Usado para visuais
  final bool canGenerate; // Controla botões de Sortear/Salvar
  final bool canReopen; // Controla botão de Reabrir

  final int maxPerTier;
  final bool considerPositions;
  final Map<String, double> playerRatings;
  final bool hasGenerated;

  final Function(bool) onTogglePositions;
  final Function(ParticipantModel, int) onMovePlayer;
  final VoidCallback? onSave;
  final VoidCallback onReopen;
  final VoidCallback onGoToSorteio;
  final VoidCallback onGenerate;

  const TiersView({
    super.key,
    required this.tiers,
    required this.goalkeepers,
    required this.isEditable,
    required this.isSaved,
    required this.canEdit,
    required this.canGenerate,
    required this.canReopen,
    required this.maxPerTier,
    required this.considerPositions,
    required this.playerRatings,
    required this.hasGenerated,
    required this.onTogglePositions,
    required this.onMovePlayer,
    this.onSave,
    required this.onReopen,
    required this.onGoToSorteio,
    required this.onGenerate,
  });

  // --- NOVO: LÓGICA DO DIÁLOGO DE MOVER ENTRE NÍVEIS ---
  void _showMoveDialog(
      BuildContext context, ParticipantModel player, int currentIndex) {
    // Definimos o nome de exibição: apelido se existir, caso contrário o nome
    final String displayName =
        player.nickname.isNotEmpty ? player.nickname : player.name;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Mover $displayName"), // Alterado aqui
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(tiers.length, (i) {
              if (i == currentIndex)
                return const SizedBox.shrink(); // Esconde o nível atual

              bool isOverLimit = tiers[i].length >= maxPerTier;

              return ListTile(
                leading: Icon(LucideIcons.arrowRightCircle, color: Colors.blue),
                title: Text("Mover para o NÍVEL ${i + 1}",
                    style: TextStyle(color: isOverLimit ? Colors.red : null)),
                subtitle: isOverLimit
                    ? const Text("Pote já está cheio",
                        style: TextStyle(color: Colors.red, fontSize: 10))
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onMovePlayer(player, i);
                },
              );
            }),
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
    final warningColor = Colors.red;

    final int totalItems = tiers.length + (goalkeepers.isNotEmpty ? 1 : 0);

    return Column(
      children: [
        if (isEditable)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.withOpacity(0.1),
            child: const Row(children: [
              Icon(LucideIcons.info, size: 16, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      "Arraste pelo ícone ou clique nas setas azuis para equilibrar os potes.",
                      style: TextStyle(fontSize: 12, color: Colors.blue)))
            ]),
          ),
        if (canEdit && isSaved)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.green.withOpacity(0.1),
            child: const Row(children: [
              Icon(LucideIcons.check, size: 16, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                  child: Text("Níveis Salvos. Para alterar, clique em Reabrir.",
                      style: TextStyle(fontSize: 12, color: Colors.green)))
            ]),
          ),
        if (!canEdit)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.withOpacity(0.1),
            child: const Row(children: [
              Icon(LucideIcons.eye, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Expanded(
                  child: Text("Modo Visualização (Somente Leitura).",
                      style: TextStyle(fontSize: 12, color: Colors.black87)))
            ]),
          ),

        if (isEditable) ...[
          CheckboxListTile(
            title: const Text("Considerar Posições?",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle:
                const Text("Tenta equilibrar defesa/ataque nos times (Beta)."),
            value: considerPositions,
            activeColor: Colors.blue,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            secondary: Icon(LucideIcons.shirt, color: Colors.blue),
            onChanged: (val) => onTogglePositions(val ?? false),
          ),
        ],
        const Divider(height: 1),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: totalItems,
            itemBuilder: (context, index) {
              // --- CARTÃO DE GOLEIROS ---
              if (goalkeepers.isNotEmpty && index == tiers.length) {
                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Theme.of(context).cardTheme.color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.purple.withOpacity(0.3))),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("NÍVEL GOLEIROS",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[700])),
                            Row(children: [
                              Icon(LucideIcons.lock,
                                  size: 14, color: Colors.purple),
                              const SizedBox(width: 4),
                              Text("${goalkeepers.length}",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple[700])),
                            ])
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 60),
                        child: Column(
                          children: goalkeepers.map<Widget>((p) {
                            return SortingPlayerTile(
                              player: p,
                              isEditable: false, // Goleiros bloqueados
                              isTeamView: false,
                              showRating: canEdit,
                              rating: playerRatings[p.uid],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // --- CARTÕES DE NÍVEIS NORMAIS ---
              int currentCount = tiers[index].length;
              bool isOverLimit = currentCount > maxPerTier;

              Widget cardContent = Card(
                elevation: isEditable ? 2 : 1,
                margin: const EdgeInsets.only(bottom: 16),
                color: Theme.of(context).cardTheme.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: (isEditable && isOverLimit)
                      ? const BorderSide(color: Colors.red, width: 2)
                      : BorderSide.none,
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isEditable && isOverLimit)
                            ? Colors.red.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("NÍVEL ${index + 1}",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: (isEditable && isOverLimit)
                                      ? warningColor
                                      : headerColor)),
                          Row(children: [
                            if (isEditable && isOverLimit)
                              Icon(LucideIcons.alertTriangle,
                                  size: 16, color: Colors.red),
                            const SizedBox(width: 4),
                            Text("$currentCount / $maxPerTier",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: (isEditable && isOverLimit)
                                        ? warningColor
                                        : subColor)),
                          ])
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Column(
                        children: tiers[index].isEmpty
                            ? <Widget>[
                                Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                        isEditable
                                            ? (hasGenerated
                                                ? "Arraste jogadores para cá"
                                                : "Clique em Sortear Níveis")
                                            : "(Vazio)",
                                        style: TextStyle(
                                            color: subColor,
                                            fontStyle: FontStyle.italic)))
                              ]
                            : tiers[index].map<Widget>((p) {
                                return SortingPlayerTile(
                                  player: p,
                                  isEditable: isEditable,
                                  isTeamView: false,
                                  showRating: canEdit,
                                  rating: playerRatings[p.uid],
                                  // --- PASSA A FUNÇÃO DO POPUP ---
                                  onOptionsTap: () =>
                                      _showMoveDialog(context, p, index),
                                );
                              }).toList(),
                      ),
                    ),
                  ],
                ),
              );

              if (isEditable) {
                return DragTarget<ParticipantModel>(
                  onAccept: (player) {
                    // --- CORREÇÃO: IGNORA SE FOR O MESMO NÍVEL ---
                    bool isAlreadyInThisTier =
                        tiers[index].any((p) => p.uid == player.uid);

                    if (!isAlreadyInThisTier) {
                      onMovePlayer(player, index);
                    } else {
                      // Opcional: print("Movimento ignorado: atleta já está neste nível.");
                    }
                  },
                  onWillAccept: (player) {
                    // Opcional: você pode checar aqui se o pote está cheio para dar feedback visual
                    return true;
                  },
                  builder: (context, candidateData, rejectedData) =>
                      candidateData.isNotEmpty
                          ? Opacity(opacity: 0.7, child: cardContent)
                          : cardContent,
                );
              }
              return cardContent;
            },
          ),
        ),

        // --- BOTÕES DE AÇÃO ---
        Container(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: isSaved
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canReopen ? onReopen : null,
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color:
                                      canReopen ? Colors.orange : Colors.grey),
                              foregroundColor:
                                  canReopen ? Colors.orange : Colors.grey),
                          icon: Icon(LucideIcons.unlock),
                          label: const Text("REABRIR"),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onGoToSorteio,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white),
                          icon: Icon(LucideIcons.arrowRight),
                          label: const Text("IR P/ SORTEIO"),
                        ),
                      )
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canGenerate ? onGenerate : null,
                          icon: Icon(LucideIcons.dices),
                          label: const Text("SORTEAR NÍVEIS"),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: canGenerate
                                      ? const Color(0xFF2E7D32)
                                      : Colors.grey),
                              foregroundColor: canGenerate
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey),
                        ),
                      ),
                      if (hasGenerated) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canGenerate ? onSave : null,
                            icon: Icon(LucideIcons.save),
                            label: const Text("SALVAR NÍVEIS"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    canGenerate ? null : Colors.grey,
                                foregroundColor: Colors.white),
                          ),
                        ),
                      ]
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
