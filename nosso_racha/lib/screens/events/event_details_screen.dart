import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/event_model.dart';
import '../../models/participant_model.dart';
import '../../models/user_model.dart';
import '../../models/payment_config_model.dart';
import '../../services/event_service.dart';
import '../../services/auth_service.dart';
import '../../services/payment_gateway_service.dart';
import '../../services/payment/payment_polling_policy.dart';
import '../../services/match_service.dart';
import '../../services/web_update_service.dart';
import 'team_sorting_screen.dart';
import 'add_player_screen.dart';
import 'create_event_screen.dart';
import 'components/payment_modal.dart';
import 'components/goalkeeper_payment_dialog.dart';
import 'components/goalkeeper_receive_pix_dialog.dart';
import '../matches/match_manager_screen.dart';
import '../matches/components/ranking_sheet.dart';

// Componentes
import 'components/master_control_bar.dart';
import 'components/event_info_header.dart';
import 'components/participant_list.dart';
import 'components/pending_join_requests.dart';
import 'components/financial_summary_modal.dart';

class EventDetailsScreen extends StatefulWidget {
  final String eventId;
  final String title;

  const EventDetailsScreen({
    super.key,
    required this.eventId,
    required this.title,
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen>
    with WidgetsBindingObserver {
  String _selectedTab = 'line';
  Timer? _timer;

  // Controle de visibilidade do cabeçalho
  bool _isHeaderExpanded = true;
  final Set<String> _goaliePixSyncAttempts = {};
  DateTime? _lastBackgroundPaymentCheckAt;
  bool _isCheckingBackgroundPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });

    if (kIsWeb) {
      Future.delayed(const Duration(seconds: 2), _checkWebVersion);
    }
  }

  Future<void> _checkWebVersion() async {
    bool hasUpdate = await WebUpdateService.checkForUpdate();
    if (hasUpdate && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.refreshCw, color: Colors.blue),
              SizedBox(width: 8),
              Text("Atualização Disponível"),
            ],
          ),
          content: const Text(
            "Uma nova versão do App LCS foi detectada. Recarregue para atualizar.",
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (kIsWeb) {
                  WebUpdateService.reloadPage();
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: const Text("ATUALIZAR"),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBackgroundPayment();
      if (kIsWeb) _checkWebVersion();
    }
  }

  Future<void> _checkBackgroundPayment() async {
    final now = DateTime.now();
    if (_isCheckingBackgroundPayment ||
        (_lastBackgroundPaymentCheckAt != null &&
            now.difference(_lastBackgroundPaymentCheckAt!) <
                PaymentPollingPolicy.interval)) {
      return;
    }

    final currentUser = Provider.of<AuthService>(
      context,
      listen: false,
    ).currentUser;
    if (currentUser == null) return;
    _isCheckingBackgroundPayment = true;
    _lastBackgroundPaymentCheckAt = now;
    final paymentService = Provider.of<PaymentGatewayService>(
      context,
      listen: false,
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .collection('pending_payments')
          .doc(currentUser.uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['payment_id'] != null &&
            PaymentPollingPolicy.shouldPoll(data)) {
          await paymentService.checkPaymentStatus(
            data['payment_id'].toString(),
          );
        }
      }
    } catch (e) {
      print("Erro ao verificar pagamento em background: $e");
    } finally {
      _isCheckingBackgroundPayment = false;
    }
  }

  // --- AÇÃO: MARCAR TODOS COMO PAGO (COM LOADING) ---
  Future<void> _markAllAsPaid(EventModel event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pagamento Geral (Retroativo)"),
        content: const Text(
          "ATENÇÃO: Isso marcará TODOS os participantes ativos como PAGOS.\n\n"
          "Use apenas para lançamentos retroativos.",
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      final firestore = FirebaseFirestore.instance;
      final eventRef = firestore.collection('events').doc(event.id);

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(eventRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;
        final participantsRaw = List<Map<String, dynamic>>.from(
          data['participants'] ?? [],
        );

        bool changed = false;
        for (var i = 0; i < participantsRaw.length; i++) {
          if (participantsRaw[i]['status'] == 'active' &&
              participantsRaw[i]['payment_status'] != 'paid') {
            participantsRaw[i]['payment_status'] = 'paid';
            changed = true;
          }
        }

        if (changed) {
          transaction.update(eventRef, {'participants': participantsRaw});
        }
      });

      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Todos marcados como pagos com sucesso!"),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Erro ao atualizar: $e")));
      }
    }
  }

  // --- AÇÃO: REABRIR EVENTO (COM LOADING) ---
  Future<void> _confirmReopenEvent(EventService service, String eventId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reabrir Evento?"),
        content: const Text(
          "O status voltará para 'Publicado'.\n\n"
          "As estatísticas deste jogo (presenças/faltas) serão removidas dos perfis dos atletas.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("REABRIR"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.orange),
                  SizedBox(height: 16),
                  Text(
                    "Processando reabertura...",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Revertendo estatísticas dos atletas.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        await service.reopenEvent(eventId);
        if (mounted) Navigator.pop(context);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Evento reaberto com sucesso!"),
              backgroundColor: Colors.green,
            ),
          );
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erro ao reabrir: $e"),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }

  // --- OUTROS MÉTODOS AUXILIARES ---
  void _showLockedAlert(BuildContext context, String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ação Bloqueada"),
        content: Text(reason, style: const TextStyle(color: Colors.red)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ENTENDI"),
          ),
        ],
      ),
    );
  }

  Future<void> _openRanking() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();
      if (mounted) Navigator.pop(context);
      if (doc.exists) {
        final data = doc.data()!;
        List<String> tier1PlayerIds = [];
        Map<String, List<ParticipantModel>> teamsMap = {};
        if (data['tiers_distribution'] != null &&
            data['tiers_distribution'] is Map) {
          final tiersMapData = Map<String, dynamic>.from(
            data['tiers_distribution'],
          );
          final sortedKeys = tiersMapData.keys.toList()..sort();
          if (sortedKeys.isNotEmpty) {
            final tier1List = List.from(tiersMapData[sortedKeys[0]] ?? []);
            tier1PlayerIds = tier1List
                .map((x) => ParticipantModel.fromMap(x).uid)
                .toList();
          }
        }
        if (data['teams_distribution'] != null &&
            data['teams_distribution'] is Map) {
          final teamsMapRaw = Map<String, dynamic>.from(
            data['teams_distribution'],
          );
          teamsMapRaw.forEach((key, value) {
            if (value is List)
              teamsMap[key] = value
                  .map((x) => ParticipantModel.fromMap(x))
                  .toList();
          });
        }
        if (mounted)
          RankingSheet.show(context, widget.eventId, teamsMap, tier1PlayerIds);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Erro ao carregar: $e")));
      }
    }
  }

  bool get _isChristmas =>
      Theme.of(context).scaffoldBackgroundColor.value == 0xFFC62828;

  void _openFinancialSummary(EventModel event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FinancialSummaryModal(event: event),
    );
  }

  void _showShareOptions(BuildContext context, EventModel event) async {
    final paymentService = Provider.of<PaymentGatewayService>(
      context,
      listen: false,
    );

    await paymentService.loadConfig(groupId: event.groupId);

    final config = paymentService.config;
    final String listText = _generateListText(event, config);

    if (!context.mounted) return;

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
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Compartilhar Lista",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(LucideIcons.share2),
                title: const Text("Compartilhar via..."),
                subtitle: const Text("WhatsApp, Telegram, etc."),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(listText);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.copy),
                title: const Text("Copiar Texto"),
                subtitle: const Text("Para colar manualmente (WhatsApp Web)"),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: listText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Lista copiada para a área de transferência!",
                      ),
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

  Future<void> _sharePrivateEventInvite(EventModel event) async {
    try {
      final inviteUri = await Provider.of<EventService>(
        context,
        listen: false,
      ).createPrivateEventInvite(event.id!);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(text: 'Convite para o evento ${event.title}: $inviteUri'),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível criar o convite: $error')),
      );
    }
  }

  String _generateListText(EventModel event, PaymentConfigModel? config) {
    StringBuffer sb = StringBuffer();
    sb.writeln("*⚽ ${event.title.toUpperCase()} ⚽*");
    sb.writeln(
      "📅 ${DateFormat('dd/MM/yyyy').format(event.startDateTime)}  🕒 ${DateFormat('HH:mm').format(event.startDateTime)}",
    );
    sb.writeln("📍 ${event.location}");
    if (event.locationNote?.isNotEmpty == true) {
      sb.writeln("📝 ${event.locationNote}");
    }
    sb.writeln("💰 Valor: R\$ ${event.price.toStringAsFixed(2)}");

    if (config != null &&
        config.provider == 'manual' &&
        config.manualPixKey.isNotEmpty) {
      sb.writeln("");
      sb.writeln("💳 *DADOS PIX*");
      sb.writeln("Chave: ${config.manualPixKey}");
      if (config.manualBeneficiary.isNotEmpty)
        sb.writeln("Nome: ${config.manualBeneficiary}");
      if (config.manualBankName.isNotEmpty)
        sb.writeln("Banco: ${config.manualBankName}");
    }

    sb.writeln("");

    final active = event.participants
        .where((p) => p.status == 'active')
        .toList();
    final goalkeepers = active
        .where((p) => p.roleInMatch == 'goalkeeper')
        .toList();
    final linePlayers = active.where((p) => p.roleInMatch == 'line').toList();

    String formatName(ParticipantModel p) {
      String name = p.nickname.isNotEmpty ? p.nickname : p.name;
      String status = p.paymentStatus == 'paid' ? " ✅" : "";
      return "$name$status";
    }

    sb.writeln("*🧤 GOLEIROS*");
    for (int i = 0; i < event.maxGoalkeepers; i++) {
      if (i < goalkeepers.length) {
        sb.writeln("${i + 1}- ${formatName(goalkeepers[i])}");
      } else {
        sb.writeln("${i + 1}- ");
      }
    }
    sb.writeln("");

    sb.writeln("*👟 JOGADORES*");
    for (int i = 0; i < event.maxLinePlayers; i++) {
      if (i < linePlayers.length) {
        sb.writeln("${i + 1}- ${formatName(linePlayers[i])}");
      } else {
        sb.writeln("${i + 1}- ");
      }
    }
    sb.writeln("");

    List<ParticipantModel> lineSuplentes = [];
    if (linePlayers.length > event.maxLinePlayers)
      lineSuplentes = linePlayers.sublist(event.maxLinePlayers);
    if (lineSuplentes.isNotEmpty) {
      sb.writeln("*⏳ SUPLENTES (Linha)*");
      for (int i = 0; i < lineSuplentes.length; i++) {
        int num = event.maxLinePlayers + i + 1;
        sb.writeln("$num- ${formatName(lineSuplentes[i])}");
      }
      sb.writeln("");
    }

    List<ParticipantModel> gkSuplentes = [];
    if (goalkeepers.length > event.maxGoalkeepers)
      gkSuplentes = goalkeepers.sublist(event.maxGoalkeepers);
    if (gkSuplentes.isNotEmpty) {
      sb.writeln("*⏳ SUPLENTES (Goleiros)*");
      for (int i = 0; i < gkSuplentes.length; i++) {
        int num = event.maxGoalkeepers + i + 1;
        sb.writeln("$num- ${formatName(gkSuplentes[i])}");
      }
    }
    sb.writeln("");
    sb.writeln("_Lista gerada pelo App LCS_");
    return sb.toString();
  }

  void _confirmPaymentToggle(
    BuildContext context,
    EventService service,
    String eventId,
    String? groupId,
    ParticipantModel player,
    UserModel currentUser,
  ) {
    bool isPaying = player.paymentStatus != 'paid';
    bool hasAutoPayment =
        player.paymentGatewayId != null && player.paymentGatewayId!.isNotEmpty;
    String title = isPaying ? "Confirmar Pagamento" : "Remover/Estornar";
    String content = isPaying
        ? "Confirmar que ${player.nickname} realizou o pagamento?"
        : "Deseja marcar o pagamento de ${player.nickname} como pendente?";

    if (!isPaying && hasAutoPayment)
      content +=
          "\n\n⚠️ Este pagamento foi feito via Mercado Pago. Ao confirmar, o valor será ESTORNADO AUTOMATICAMENTE.";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (!isPaying && hasAutoPayment) {
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Processando estorno..."),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  final paymentService = Provider.of<PaymentGatewayService>(
                    context,
                    listen: false,
                  );
                  await paymentService.refundPix(
                    player.paymentGatewayId!,
                    groupId: groupId,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Estorno realizado com sucesso!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro ao estornar: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
              }
              service.togglePaymentStatus(eventId, player.uid, currentUser);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaying ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(
              isPaying
                  ? "CONFIRMAR"
                  : (hasAutoPayment ? "ESTORNAR" : "REMOVER"),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmGoalkeeperPaymentReceived(
    EventService service,
    String eventId,
    ParticipantModel participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar recebimento'),
        content: const Text(
          'Confirme somente se o valor do Pix já entrou na sua conta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Ainda não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar recebimento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await service.confirmGoalkeeperPaymentReceived(
        eventId: eventId,
        goalkeeperUid: participant.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recebimento confirmado.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível confirmar: $error')),
      );
    }
  }

  Widget _buildGoalkeeperPaymentPanel(
    EventService service,
    EventModel event,
    ParticipantModel participant,
  ) {
    if (participant.roleInMatch != 'goalkeeper') {
      return const SizedBox.shrink();
    }

    return StreamBuilder(
      stream: service.getGoaliePaymentStream(widget.eventId, participant.uid),
      builder: (context, snapshot) {
        final payment = snapshot.data?.data();
        final status =
            payment?['goalie_payment_status'] as String? ??
            participant.goaliePaymentStatus;
        final pixKey = payment?['pix_key'] as String? ?? '';
        if (status == 'none') {
          if (snapshot.hasError) {
            return const Card(
              margin: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: Icon(Icons.error_outline, color: Colors.red),
                title: Text('Não foi possível carregar sua chave Pix.'),
              ),
            );
          }
          if (pixKey.isEmpty) {
            return const Card(
              margin: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('QR Pix para receber'),
                subtitle: Text(
                  'Cadastre uma chave Pix no perfil para gerar seu QR. '
                  'O cadastro é opcional.',
                ),
              ),
            );
          }
          return Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Receber pagamento por Pix'),
              subtitle: const Text(
                'Mostre seu QR Pix para o organizador escanear no racha.',
              ),
              trailing: IconButton(
                tooltip: 'Gerar QR Pix',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => showGoalkeeperReceivePixDialog(
                  context: context,
                  pixKey: pixKey,
                  goalkeeperName: participant.name,
                ),
              ),
              onTap: () => showGoalkeeperReceivePixDialog(
                context: context,
                pixKey: pixKey,
                goalkeeperName: participant.name,
              ),
            ),
          );
        }

        final isConfirmed = status == 'confirmed';
        final amount =
            (payment?['amount'] as num?)?.toDouble() ?? event.goalkeeperAid;
        final amountDisplay = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(amount);
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            leading: Icon(
              isConfirmed ? Icons.check_circle : Icons.payments_outlined,
              color: isConfirmed ? Colors.green : Colors.orange,
            ),
            title: Text(
              isConfirmed
                  ? 'Pagamento recebido e confirmado'
                  : 'O organizador marcou seu pagamento',
            ),
            subtitle: Text(
              isConfirmed
                  ? 'Valor: $amountDisplay'
                  : 'Confirme somente após o valor cair na sua conta. '
                        'Valor: $amountDisplay',
            ),
            trailing: status == 'pending_confirmation'
                ? TextButton(
                    onPressed: () => _confirmGoalkeeperPaymentReceived(
                      service,
                      widget.eventId,
                      participant,
                    ),
                    child: const Text('Confirmar recebimento'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _syncGoalkeeperPixKey(
    EventService service,
    UserModel user,
    String eventId,
  ) async {
    try {
      await service.syncGoaliePixKey(eventId, user);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível atualizar a chave Pix: $error'),
        ),
      );
    }
  }

  void _confirmRemovePlayer(
    BuildContext context,
    EventService service,
    String eventId,
    ParticipantModel player,
    bool isListLocked,
  ) {
    if (player.paymentStatus == 'paid') {
      _showLockedAlert(
        context,
        "O atleta ${player.nickname} consta como PAGO. Estorne o valor antes de remover.",
      );
      return;
    }
    if (isListLocked) {
      _showLockedAlert(
        context,
        "Níveis já definidos! Para remover alguém agora, reabra os níveis na tela de Sorteio.",
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remover Atleta"),
        content: Text(
          "Tem certeza que deseja remover ${player.nickname} da lista?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              service.leaveEvent(eventId, player.uid);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("REMOVER"),
          ),
        ],
      ),
    );
  }

  void _onReorder(
    int oldIndex,
    int newIndex,
    EventModel event,
    EventService service,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final allActive = event.participants
        .where((p) => p.status == 'active')
        .toList();
    final currentTabPlayers = allActive
        .where((p) => p.roleInMatch == _selectedTab)
        .toList();
    final otherTabPlayers = allActive
        .where((p) => p.roleInMatch != _selectedTab)
        .toList();
    final inactivePlayers = event.participants
        .where((p) => p.status != 'active')
        .toList();

    final item = currentTabPlayers.removeAt(oldIndex);
    currentTabPlayers.insert(newIndex, item);

    final capacity = _selectedTab == 'goalkeeper'
        ? event.maxGoalkeepers
        : event.maxLinePlayers;
    for (int i = 0; i < currentTabPlayers.length; i++) {
      final p = currentTabPlayers[i];
      if (i >= capacity && p.paymentStatus == 'paid') {
        _showLockedAlert(
          context,
          "Ação Negada!\n\nO atleta ${p.name} já pagou e não pode ser movido para a lista de espera. Estorne o pagamento primeiro.",
        );
        return;
      }
    }
    final newFullList = [
      ...otherTabPlayers,
      ...currentTabPlayers,
      ...inactivePlayers,
    ];
    try {
      await service.updateParticipantsOrder(event.id!, newFullList);
    } catch (e) {
      // Isso captura a exceção que lançamos no service
      _showLockedAlert(context, e.toString());
    }
    //service.updateParticipantsOrder(event.id!, newFullList);
  }

  void _handleJoinEvent(
    BuildContext context,
    EventService service,
    String eventId,
    UserModel user,
    EventModel event,
  ) {
    final isGoleiro =
        event.sportHasGoalkeeper &&
        event.allowGoalkeepers &&
        (user.canPlayMultiplePositions || user.positions.contains('Goleiro'));
    final isLinha =
        event.allowLinePlayers &&
        (user.canPlayMultiplePositions ||
            user.positions.any((position) => position != 'Goleiro'));
    if (!isGoleiro && !isLinha) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sua posição ou as vagas deste evento não permitem esta inscrição.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (isGoleiro && isLinha) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Em qual posição vai jogar?"),
          content: const Text(
            "Você joga no gol e na linha. Escolha para hoje:",
          ),
          actions: [
            TextButton.icon(
              icon: Icon(LucideIcons.shield),
              label: const Text("GOLEIRO"),
              style: TextButton.styleFrom(foregroundColor: Colors.purple),
              onPressed: () {
                Navigator.pop(ctx);
                _joinEvent(service, eventId, user, 'goalkeeper');
              },
            ),
            ElevatedButton.icon(
              icon: Icon(LucideIcons.user),
              label: const Text("LINHA"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _joinEvent(service, eventId, user, 'line');
              },
            ),
          ],
        ),
      );
    } else if (isGoleiro) {
      _joinEvent(service, eventId, user, 'goalkeeper');
    } else {
      _joinEvent(service, eventId, user, 'line');
    }
  }

  Future<void> _joinEvent(
    EventService service,
    String eventId,
    UserModel user,
    String role,
  ) async {
    try {
      final result = await service.joinEvent(eventId, user, role: role);
      if (!mounted) return;
      final message = switch (result) {
        'requested' =>
          'Solicitação enviada. Aguarde a aprovação do organizador.',
        'queue' => 'Você entrou na fila de espera.',
        'active' => 'Você já está inscrito neste evento.',
        _ => 'Inscrição confirmada.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildBlindListState(
    bool amIConfirmed,
    bool isDark,
    DateTime? votingOpensAt,
  ) {
    final textColor = _isChristmas
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);
    final subColor = _isChristmas ? Colors.white70 : Colors.grey;

    String waitMessage = "Aguarde a divulgação oficial do Master.";
    if (votingOpensAt != null && DateTime.now().isBefore(votingOpensAt)) {
      final dateStr = DateFormat('dd/MM HH:mm').format(votingOpensAt);
      waitMessage = "Confirmações abrem em: $dateStr";
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            amIConfirmed ? LucideIcons.checkCircle : LucideIcons.eyeOff,
            size: 64,
            color: amIConfirmed ? Colors.green : subColor,
          ),
          const SizedBox(height: 16),
          Text(
            amIConfirmed
                ? "Você está confirmado!"
                : "A lista de jogadores está oculta.",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            waitMessage,
            style: TextStyle(color: subColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- MÉTODOS DE SÚMULA ---
  String _generateClosingReport(EventModel event) {
    StringBuffer sb = StringBuffer();
    sb.writeln("*📋 SÚMULA FINAL - ${event.title.toUpperCase()}*");
    sb.writeln(
      "📅 Data: ${DateFormat('dd/MM/yyyy').format(event.startDateTime)}",
    );
    sb.writeln("");

    // Lê os dados da lista de fechamento isolada
    final listToUse = event.status == 'finished' && event.closingList.isNotEmpty
        ? event.closingList
        : event.participants;
    final presentes = listToUse
        .where((p) => p.attendance == 'present')
        .toList();
    final faltas = listToUse.where((p) => p.attendance == 'absent').toList();

    sb.writeln("*✅ PRESENTES (${presentes.length})*");
    for (var p in presentes) {
      String name = p.nickname.isNotEmpty ? p.nickname : p.name;
      String extra = p.isAvulso ? " (Avulso)" : "";
      sb.writeln("- $name$extra");
    }

    sb.writeln("");
    sb.writeln("*❌ FALTAS / NO-SHOW (${faltas.length})*");
    if (faltas.isEmpty) sb.writeln("(Nenhuma falta registrada)");
    for (var p in faltas) {
      String name = p.nickname.isNotEmpty ? p.nickname : p.name;
      sb.writeln("- $name");
    }

    sb.writeln("");
    sb.writeln("_Relatório de fechamento LCS_");
    return sb.toString();
  }

  void _showClosingReport(EventModel event) {
    final report = _generateClosingReport(event);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Súmula do Jogo"),
        content: SingleChildScrollView(
          child: SelectableText(
            report,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Copiado para a área de transferência!"),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.pop(ctx);
            },
            icon: Icon(LucideIcons.copy),
            label: const Text("COPIAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("FECHAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventService = Provider.of<EventService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return StreamBuilder<DocumentSnapshot>(
      stream: eventService.getEventDetailStream(widget.eventId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(
              child: Text(
                'Este evento é privado ou você não tem acesso a ele.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData)
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        if (!snapshot.data!.exists)
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: Text("Evento não encontrado.")),
          );

        final eventData = snapshot.data!.data() as Map<String, dynamic>;
        final event = EventModel.fromMap(snapshot.data!.id, eventData);

        final myEntryIndex = event.participants.indexWhere(
          (p) => p.uid == currentUser.uid,
        );
        if (myEntryIndex >= 0 &&
            event.participants[myEntryIndex].roleInMatch == 'goalkeeper' &&
            _goaliePixSyncAttempts.add(widget.eventId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(
              _syncGoalkeeperPixKey(eventService, currentUser, widget.eventId),
            );
          });
        }
        final isConfirmed =
            myEntryIndex >= 0 &&
            event.participants[myEntryIndex].status == 'active';
        final isPaid =
            myEntryIndex >= 0 &&
            event.participants[myEntryIndex].paymentStatus == 'paid';

        final bool isStaffOrMaster =
            currentUser.isMaster || currentUser.role == 'org';
        final bool isBlindList =
            (event.status == 'scheduled' || event.status == 'curating');
        final bool canViewFullList = isStaffOrMaster || !isBlindList;

        final activeParticipants = event.participants
            .where((p) => p.status == 'active' && !p.isAvulso)
            .toList();

        bool isTitular = false;
        if (isConfirmed) {
          final myEntry = event.participants[myEntryIndex];
          final myRole = myEntry.roleInMatch;
          final myList = activeParticipants
              .where((p) => p.roleInMatch == myRole)
              .toList();
          final myRank = myList.indexWhere((p) => p.uid == currentUser.uid);
          final limit = myRole == 'goalkeeper'
              ? event.maxGoalkeepers
              : event.maxLinePlayers;
          isTitular = myRank != -1 && myRank < limit;
        }

        final displayedList = activeParticipants
            .where((p) => p.roleInMatch == _selectedTab)
            .toList();
        final countLine = activeParticipants
            .where((p) => p.roleInMatch == 'line')
            .length;
        final countGk = activeParticipants
            .where((p) => p.roleInMatch == 'goalkeeper')
            .length;

        final bool isVotingOpen = DateTime.now().isAfter(event.votingOpensAt);
        final bool tiersLocked = eventData['tiers_locked'] == true;
        final bool teamsLocked = eventData['teams_locked'] == true;
        final bool hasTeamsSaved =
            event.teamsDistribution != null &&
            event.teamsDistribution!.isNotEmpty;
        final bool hasTiersSaved =
            event.tiersDistribution != null &&
            event.tiersDistribution!.isNotEmpty;

        bool canViewSorting = isStaffOrMaster
            ? (hasTeamsSaved || hasTiersSaved)
            : (hasTeamsSaved && hasTiersSaved);
        final bool canViewMatches = hasTeamsSaved && teamsLocked;

        // --- CORREÇÃO: VERIFICA SE OS NÍVEIS OU TIMES ESTÃO BLOQUEADOS ---
        final bool isListClosedForAthlete = tiersLocked || teamsLocked;

        final bool isListLocked = tiersLocked || teamsLocked;

        return Scaffold(
          appBar: AppBar(
            title: Text(event.title.isNotEmpty ? event.title : widget.title),
            actions: [
              if (event.createdBy == currentUser.uid || event.groupId != null)
                PendingJoinRequests(
                  eventId: widget.eventId,
                  eventService: eventService,
                  groupId: event.groupId,
                  userId: currentUser.uid,
                  isEventCreator: event.createdBy == currentUser.uid,
                ),
              if (canViewSorting)
                IconButton(
                  icon: Icon(LucideIcons.shirt),
                  tooltip: "Times",
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TeamSortingScreen(event: event),
                    ),
                  ),
                ),
              if (currentUser.canViewFinancialSummary)
                IconButton(
                  icon: Icon(LucideIcons.wallet),
                  tooltip: "Resumo Financeiro",
                  onPressed: () => _openFinancialSummary(event),
                ),
              if (hasTeamsSaved)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .doc(widget.eventId)
                      .collection('matches')
                      .limit(1)
                      .snapshots(),
                  builder: (ctx, snap) =>
                      (snap.hasData && snap.data!.docs.isNotEmpty)
                      ? IconButton(
                          icon: Icon(LucideIcons.trophy),
                          onPressed: _openRanking,
                        )
                      : const SizedBox.shrink(),
                ),
              if (canViewMatches)
                IconButton(
                  icon: Icon(LucideIcons.playCircle),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChangeNotifierProvider(
                        create: (_) => MatchService(),
                        child: MatchManagerScreen(event: event),
                      ),
                    ),
                  ),
                ),
              if ((event.status == 'published' || event.status == 'finished') &&
                  currentUser.canShareList)
                IconButton(
                  icon: Icon(LucideIcons.share2),
                  onPressed: () => _showShareOptions(context, event),
                ),
              if (event.visibility == 'private' &&
                  (currentUser.isStaff ||
                      currentUser.canEditEvent ||
                      currentUser.canCreateEvent) &&
                  event.status != 'finished')
                IconButton(
                  icon: const Icon(Icons.link),
                  tooltip: 'Criar convite para este evento privado',
                  onPressed: () => _sharePrivateEventInvite(event),
                ),
              if (event.status != 'finished' && currentUser.canEditEvent)
                IconButton(
                  icon: Icon(LucideIcons.pencil),
                  onPressed: () {
                    if (isListLocked)
                      _showLockedAlert(context, "Sorteio em andamento!");
                    else
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              CreateEventScreen(eventToEdit: event),
                        ),
                      );
                  },
                ),
              if (currentUser.canAddPlayer)
                IconButton(
                  icon: Icon(LucideIcons.userPlus),
                  onPressed: () {
                    if (isListLocked)
                      _showLockedAlert(context, "Sorteio definido.");
                    else
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AddPlayerScreen(
                            eventId: widget.eventId,
                            existingParticipantIds: event.participants
                                .where((p) => p.status == 'active')
                                .map((p) => p.uid)
                                .toList(),
                          ),
                        ),
                      );
                  },
                ),
              if (event.status == 'finished')
                IconButton(
                  icon: Icon(LucideIcons.clipboardCheck),
                  tooltip: "Ver Súmula",
                  onPressed: () => _showClosingReport(event),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _isHeaderExpanded
                        ? Column(
                            children: [
                              MasterControlBar(
                                event: event,
                                user: currentUser,
                                isListLocked: isListLocked,
                                onReopen: () => _confirmReopenEvent(
                                  eventService,
                                  widget.eventId,
                                ),
                                onMarkPaid: () => _markAllAsPaid(event),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  EventInfoHeader(
                    event: event,
                    selectedTab: _selectedTab,
                    countLine: countLine,
                    countGk: countGk,
                    canViewFullList: canViewFullList,
                    onTabChanged: (val) => setState(() => _selectedTab = val),
                    isExpanded: _isHeaderExpanded,
                    onToggleExpand: () =>
                        setState(() => _isHeaderExpanded = !_isHeaderExpanded),
                  ),
                  const Divider(height: 1),
                  if (myEntryIndex >= 0)
                    _buildGoalkeeperPaymentPanel(
                      eventService,
                      event,
                      event.participants[myEntryIndex],
                    ),
                  Expanded(
                    child: !canViewFullList
                        ? _buildBlindListState(
                            isConfirmed,
                            isDark,
                            event.votingOpensAt,
                          )
                        : ParticipantList(
                            participants: displayedList,
                            event: event,
                            currentUser: currentUser,
                            eventId: widget.eventId,
                            eventService: eventService,
                            isListLocked: isListLocked,
                            isDark: isDark,
                            onPaymentToggle: (p) => _confirmPaymentToggle(
                              context,
                              eventService,
                              widget.eventId,
                              event.groupId,
                              p,
                              currentUser,
                            ),
                            onGoalkeeperPayment: (p) =>
                                showGoalkeeperPaymentDialog(
                                  context: context,
                                  event: event,
                                  goalkeeper: p,
                                  organizer: currentUser,
                                  eventService: eventService,
                                ),
                            onRemovePlayer: (p) => _confirmRemovePlayer(
                              context,
                              eventService,
                              widget.eventId,
                              p,
                              isListLocked,
                            ),
                            onReorder: (o, n) =>
                                _onReorder(o, n, event, eventService),
                          ),
                  ),
                  if (!isStaffOrMaster && !isConfirmed)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: eventService.getJoinRequestStream(
                        widget.eventId,
                        currentUser.uid,
                      ),
                      builder: (context, requestSnapshot) {
                        if (requestSnapshot.data?.data()?['status'] !=
                            'pending') {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Sua solicitação aguarda aprovação.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await eventService.cancelJoinRequest(
                                      widget.eventId,
                                      currentUser.uid,
                                    );
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          error.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Cancelar'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (event.status != 'finished')
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        16 + bottomPadding,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Consumer<EventService>(
                        builder: (context, service, _) {
                          if (service.isLoading)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );

                          if (isConfirmed) {
                            return Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      if (isPaid)
                                        _showLockedAlert(context, "Já pago.");
                                      else if (isListLocked)
                                        _showLockedAlert(
                                          context,
                                          "Sorteio em andamento. Não é possível sair agora.",
                                        );
                                      else
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              "Confirma a desistência do racha?",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text("NÃO"),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  service.leaveEvent(
                                                    widget.eventId,
                                                    currentUser.uid,
                                                  );
                                                },
                                                child: const Text("SIM"),
                                              ),
                                            ],
                                          ),
                                        );
                                    },
                                    icon: Icon(LucideIcons.xCircle),
                                    label: const Text("DESISTIR"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (isTitular &&
                                    !isPaid &&
                                    event.status == 'published')
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(20),
                                          ),
                                        ),
                                        builder: (_) => PaymentModal(
                                          event: event,
                                          user: currentUser,
                                        ),
                                      ),
                                      icon: Icon(LucideIcons.qrCode),
                                      label: const Text("PAGAR"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                    ),
                                  )
                                else if (!isTitular && !isPaid)
                                  const Expanded(child: SizedBox.shrink()),
                                if (isPaid)
                                  Expanded(
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.check,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "PAGO",
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          } else {
                            if (isListClosedForAthlete) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.red[900]!.withOpacity(0.3)
                                      : Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.5),
                                  ),
                                ),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.lock, color: Colors.red),
                                    SizedBox(height: 4),
                                    Text(
                                      "Inscrições Encerradas",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    Text(
                                      "O sorteio já foi iniciado pela organização.",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (!isVotingOpen && !isStaffOrMaster) {
                              final diff = event.votingOpensAt.difference(
                                DateTime.now(),
                              );
                              String timeText = diff.inHours > 0
                                  ? "${diff.inHours}h ${diff.inMinutes % 60}m"
                                  : "${diff.inMinutes}m ${diff.inSeconds % 60}s";
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.lock, color: Colors.grey),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "Inscrições abrem em:",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      timeText,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "(${DateFormat("dd/MM/yyyy 'às' HH:mm").format(event.votingOpensAt)})",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: service.getJoinRequestStream(
                                widget.eventId,
                                currentUser.uid,
                              ),
                              builder: (context, requestSnapshot) {
                                final isRequestPending =
                                    requestSnapshot.data?.data()?['status'] ==
                                    'pending';
                                return SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: isRequestPending
                                        ? null
                                        : () => _handleJoinEvent(
                                            context,
                                            service,
                                            widget.eventId,
                                            currentUser,
                                            event,
                                          ),
                                    icon: Icon(
                                      isRequestPending
                                          ? LucideIcons.clock
                                          : LucideIcons.checkCircle,
                                    ),
                                    label: Text(
                                      isRequestPending
                                          ? 'AGUARDANDO APROVAÇÃO'
                                          : 'QUERO JOGAR',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
