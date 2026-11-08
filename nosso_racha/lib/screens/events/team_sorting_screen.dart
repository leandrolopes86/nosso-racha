import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../models/event_model.dart';
import '../../services/auth_service.dart';

// Controller
import 'controllers/team_sorting_controller.dart';

// Views
import 'tabs/tiers_view.dart';
import 'tabs/teams_view.dart';

class TeamSortingScreen extends StatelessWidget {
  final EventModel event;

  const TeamSortingScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;

    return ChangeNotifierProvider(
      create: (_) => TeamSortingController(event: event, currentUser: user),
      child: const _TeamSortingScreenContent(),
    );
  }
}

class _TeamSortingScreenContent extends StatefulWidget {
  const _TeamSortingScreenContent();

  @override
  State<_TeamSortingScreenContent> createState() =>
      _TeamSortingScreenContentState();
}

class _TeamSortingScreenContentState extends State<_TeamSortingScreenContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Avisa que entrou
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TeamSortingController>(
        context,
        listen: false,
      ).setPresence(true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- HANDLERS DE UI (Diálogos e SnackBars) ---

  void _handleShare(BuildContext context, TeamSortingController controller) {
    int index = _tabController.index;
    String textToShare = "";
    String title = "";

    if (index == 0) {
      textToShare = controller.generateTiersText();
      title = "Compartilhar Níveis";
    } else {
      if (!controller.teamsGenerated && !controller.teamsSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Nada para compartilhar ainda.")),
        );
        return;
      }
      textToShare = controller.generateTeamsText();
      title = "Compartilhar Times";
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(LucideIcons.share2),
                title: const Text("Compartilhar via..."),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(textToShare);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.copy),
                title: const Text("Copiar Texto"),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: textToShare));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Copiado!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleSaveTiers(
    BuildContext context,
    TeamSortingController controller,
  ) async {
    final error = await controller.saveTiers();
    if (error != null) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
    } else {
      if (context.mounted) {
        bool? wantToShare = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Níveis Salvos!"),
            content: const Text(
              "Deseja compartilhar a definição dos níveis agora?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("NÃO"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("SIM"),
              ),
            ],
          ),
        );
        if (wantToShare == true) _handleShare(context, controller);
        _tabController.animateTo(1);
      }
    }
  }

  Future<void> _handleSaveTeams(
    BuildContext context,
    TeamSortingController controller,
  ) async {
    final error = await controller.saveTeams();
    if (error != null) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
    } else {
      if (context.mounted) {
        bool? wantToShare = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Times Salvos!"),
            content: const Text(
              "Deseja compartilhar os times sorteados agora?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("NÃO"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("SIM"),
              ),
            ],
          ),
        );
        if (wantToShare == true) _handleShare(context, controller);
      }
    }
  }

  void _confirmReopen(
    BuildContext context,
    VoidCallback onConfirm,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tem certeza?"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );
  }

  // Animação de Sorteio
  Future<void> _sortWithAnimation(
    BuildContext context,
    TeamSortingController controller,
  ) async {
    if (!controller.tiersSaved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Salve os níveis antes.")));
      _tabController.animateTo(0);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (context.mounted) {
      Navigator.pop(context);
      controller.generateTeamsFromTiers();
      _tabController.animateTo(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<TeamSortingController>(context);

    final hasChanges = controller.hasMismatchedParticipants;

    // Exclui o próprio usuário da contagem (quem está editando além de mim)
    final otherUsersCount = controller.activeUsers.isNotEmpty
        ? controller.activeUsers.length - 1
        : 0;
    final user = controller.currentUser;
    //print("Mudança: $hasChanges");
    // Permissões
    final canGenerateTiers = user != null && user.canGenerateTiers;
    final canReopenTiers = user != null && user.canReopenTiers;
    final canSortTeams = user != null && user.canSortTeams;
    final canReopenTeams = user != null && user.canReopenTeams;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Sorteio de Times"),
            if (otherUsersCount > 0)
              Text(
                "$otherUsersCount pessoa(s) editando simultaneamente...",
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orangeAccent,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.share2),
            onPressed: () => _handleShare(context, controller),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "1. Níveis (Potes)"),
            Tab(text: "2. Resultado"),
          ],
        ),
      ),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          // mexer aqui
          : Column(
              children: [
                // ALERTA VISUAL
                if (hasChanges && !controller.tiersSaved)
                  Container(
                    width: double.infinity,
                    color: Colors.redAccent,
                    padding: const EdgeInsets.all(10),
                    child: const Text(
                      "⚠️ Lista de confirmados alterada! Gere os níveis novamente.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      TiersView(
                        tiers: controller.tiers,
                        goalkeepers: controller.goalkeepers,
                        isEditable:
                            canGenerateTiers &&
                            !controller.tiersSaved &&
                            !hasChanges,
                        isSaved: controller.tiersSaved,
                        canEdit: canGenerateTiers,
                        canGenerate: canGenerateTiers,
                        canReopen: canReopenTiers,
                        maxPerTier: controller.event.numberOfTeams,
                        considerPositions: controller.considerPositions,
                        playerRatings: controller.playerRatings,
                        hasGenerated: controller.tiersGenerated,
                        onTogglePositions: controller.togglePositions,
                        onMovePlayer: controller.movePlayerBetweenTiers,
                        onSave: hasChanges
                            ? null
                            : () => _handleSaveTiers(context, controller),
                        //onSave: () => _handleSaveTiers(context, controller),
                        onReopen: () {
                          if (controller.teamsSaved) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Ação Bloqueada"),
                                content: const Text(
                                  "O resultado final dos times já foi salvo.\n\n"
                                  "Para reabrir os Níveis, você precisa primeiro ir na aba 'Resultado' e clicar em 'REABRIR SORTEIO'.",
                                  style: TextStyle(color: Colors.red),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("ENTENDI"),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            _confirmReopen(
                              context,
                              controller.reopenTiers,
                              "Reabrir edição de níveis?",
                            );
                          }
                        },
                        onGenerate: hasChanges
                            ? () {
                                // Opcional: avisar o usuário que ele precisa atualizar
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Lista desatualizada! O sorteio será recriado com os novos dados.",
                                    ),
                                  ),
                                );
                                controller.generateTiers();
                              }
                            : controller.generateTiers,
                        onGoToSorteio: () {
                          _tabController.animateTo(1);
                          if (!controller.teamsGenerated && canSortTeams)
                            _sortWithAnimation(context, controller);
                        },
                      ),
                      TeamsView(
                        generatedTeams: controller.generatedTeams,
                        isEditable: canSortTeams && !controller.teamsSaved,
                        isGenerated: controller.teamsGenerated,
                        isSaved: controller.teamsSaved,
                        canEdit: canSortTeams,
                        canSort: canSortTeams,
                        canReopen: canReopenTeams,
                        tiersSaved: controller.tiersSaved,
                        maxPerTeam: controller.event.linePlayersPerTeam,
                        includeGoalkeepers: controller.includeGoalkeepers,
                        tiers: controller.tiers,
                        onSort: () => _sortWithAnimation(context, controller),
                        onSave: () => _handleSaveTeams(context, controller),
                        onReopen: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.orange,
                              ),
                            ),
                          );

                          try {
                            final eventDoc = await FirebaseFirestore.instance
                                .collection('events')
                                .doc(controller.event.id)
                                .get();
                            final matchesSnap = await FirebaseFirestore.instance
                                .collection('events')
                                .doc(controller.event.id)
                                .collection('matches')
                                .limit(1)
                                .get();

                            if (context.mounted) Navigator.pop(context);

                            bool hasMatches = matchesSnap.docs.isNotEmpty;
                            bool isPlaying =
                                eventDoc.data()?['current_match_data'] != null;

                            if (hasMatches || isPlaying) {
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Ação Bloqueada"),
                                    content: const Text(
                                      "Não é possível reabrir o sorteio pois já existem jogos em andamento ou no histórico.\n\n"
                                      "Para reabrir o sorteio, você precisa primeiro cancelar o jogo atual e excluir as partidas salvas na tela de Sequência de Jogos.",
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text("ENTENDI"),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return;
                            }

                            if (context.mounted) {
                              _confirmReopen(
                                context,
                                controller.reopenTeams,
                                "Reabrir sorteio? Isso apagará a distribuição atual.",
                              );
                            }
                          } catch (e) {
                            if (context.mounted) Navigator.pop(context);
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Erro ao verificar jogos: $e"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                          }
                        },
                        onMovePlayer: (p, teamIndex) {
                          bool success = controller.movePlayerBetweenTeams(
                            p,
                            teamIndex,
                          );
                          if (!success) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Trocar Goleiros?"),
                                content: const Text(
                                  "Este time já tem goleiro. Deseja trocar?",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("CANCELAR"),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      controller.forceSwapGoalkeepers(
                                        p,
                                        teamIndex,
                                      );
                                    },
                                    child: const Text("TROCAR"),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        onReorderTeams: controller.reorderTeams,
                        onToggleGoalkeepers: controller.toggleGoalkeepers,
                        onReorderWithinTeam: controller.reorderPlayerWithinTeam,
                        // --- INJETA A NOVA FUNÇÃO DE ORDENAÇÃO ---
                        onSortTeam: controller.sortTeamByTier,
                        getSlottedLinePlayers: controller.getSlottedLinePlayers,
                        getPlayerTier: controller.getPlayerTier,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
