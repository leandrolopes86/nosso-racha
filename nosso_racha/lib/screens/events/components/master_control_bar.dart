import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/event_model.dart';
import '../../../models/user_model.dart';
import '../../../services/event_service.dart';
import '../../../services/payment_gateway_service.dart';
import '../team_sorting_screen.dart';
import '../event_closing_screen.dart';

class MasterControlBar extends StatefulWidget {
  final EventModel event;
  final UserModel user;
  final bool isListLocked;

  // Callbacks recebidos da tela pai (EventDetailsScreen)
  final VoidCallback onReopen;
  final VoidCallback onMarkPaid;

  const MasterControlBar({
    super.key,
    required this.event,
    required this.user,
    required this.isListLocked,
    required this.onReopen, // <--- Recebe a função de reabrir
    required this.onMarkPaid, // <--- Recebe a função de pagar tudo
  });

  @override
  State<MasterControlBar> createState() => _MasterControlBarState();
}

class _MasterControlBarState extends State<MasterControlBar> {
  bool _isVerifyingPayments = false;

  Future<void> _forceSyncPayments() async {
    if (_isVerifyingPayments) return;

    setState(() => _isVerifyingPayments = true);
    final paymentService = Provider.of<PaymentGatewayService>(
      context,
      listen: false,
    );
    int confirmedCount = 0;

    try {
      final pendingCandidates = widget.event.participants
          .where(
            (p) =>
                p.status == 'active' &&
                p.paymentStatus == 'pending' &&
                p.paymentGatewayId != null &&
                p.paymentGatewayId!.isNotEmpty &&
                !p.paymentGatewayId!.startsWith('manual_'),
          )
          .toList();

      if (pendingCandidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Nenhum pagamento automático pendente para verificar.",
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "A sincronizar ${pendingCandidates.length} pagamentos...",
          ),
        ),
      );

      for (var p in pendingCandidates) {
        final status = await paymentService.checkPaymentStatus(
          p.paymentGatewayId!,
        );
        if (status == 'approved') {
          confirmedCount++;
        }
      }

      if (confirmedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "$confirmedCount pagamentos confirmados! A lista foi atualizada.",
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Nenhum novo pagamento encontrado.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro na sincronização: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isVerifyingPayments = false);
    }
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
            child: const Text("ENTENDI"),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveUnpaid(EventService service, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remover Não Pagos"),
        content: Text(
          "Tem a certeza que deseja remover $count atletas TITULARES ativos que ainda não pagaram?\n\nOs suplentes subirão automaticamente.",
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              // --- ADICIONADO TRATAMENTO DE ERRO E AWAIT ---
              try {
                // A permissão do Firestore estava a causar "permission denied" se a Cloud Function tentasse aceder sem auth de Master/Owner.
                // Mas, como a remoção é feita pelo serviço local (EventService) e o user logado tem a permissão 'canRemoveUnpaid' (que checa isMaster ou flag),
                // o erro deve-se a alguma regra do firestore barrar a ação. O catch vai apanhar o erro exacto.
                await service.removeUnpaidParticipants(widget.event.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Atletas removidos com sucesso!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  // Apresenta o erro completo para identificar se é permissão negada.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro ao remover: $e"),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("REMOVER TODOS"),
          ),
        ],
      ),
    );
  }

  // --- NOVA LÓGICA DE CONTAGEM DE TITULARES NÃO PAGOS ---
  int _calculateUnpaidTitularsCount() {
    int unpaidTitulars = 0;
    int currentGkCount = 0;
    int currentLineCount = 0;

    // Filtra apenas os participantes ativos
    final activeParticipants = widget.event.participants
        .where((p) => p.status == 'active')
        .toList();

    for (var p in activeParticipants) {
      bool isTitular = false;

      // Verifica se é titular baseado na posição
      if (p.roleInMatch == 'goalkeeper') {
        currentGkCount++;
        if (currentGkCount <= widget.event.maxGoalkeepers) {
          isTitular = true;
        }
      } else {
        currentLineCount++;
        if (currentLineCount <= widget.event.maxLinePlayers) {
          isTitular = true;
        }
      }

      // Se for titular e não pagou, incrementa
      // Goleiros normalmente pagam, mas se houver regra de goleiro não pagar, a lógica do seu app já cobre isso
      // no botão pagar. Assumindo que a regra base é "todos os titulares ativos devem pagar":
      if (isTitular &&
          p.paymentStatus != 'paid' &&
          p.roleInMatch != 'goalkeeper') {
        unpaidTitulars++;
      }
    }

    return unpaidTitulars;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.user.isStaff) return const SizedBox.shrink();

    final service = Provider.of<EventService>(context, listen: false);
    final event = widget.event;
    final user = widget.user;

    bool showPublish = event.status == 'scheduled' && (user.canEditEvent);
    bool showSort =
        event.status == 'published' &&
        event.confirmedCount > 0 &&
        (user.canGenerateTiers || user.canSortTeams);
    bool showClose = event.status == 'published' && user.canEndEvent;
    bool showReopen = event.status == 'finished' && user.canEndEvent;

    // CORREÇÃO: Conta APENAS titulares que não pagaram
    int unpaidTitularsCount = _calculateUnpaidTitularsCount();

    // O botão só aparece se existirem titulares não pagos E o user tiver permissão
    bool showRemoveUnpaid =
        event.status == 'published' &&
        unpaidTitularsCount > 0 &&
        user.canRemoveUnpaid;

    bool hasPendingGatewayPayments = event.participants.any(
      (p) =>
          p.status == 'active' &&
          p.paymentStatus == 'pending' &&
          p.paymentGatewayId != null &&
          p.paymentGatewayId!.isNotEmpty,
    );
    bool canSync = user.canSyncPayments;

    if (!showPublish &&
        !showSort &&
        !showClose &&
        !showReopen &&
        !showRemoveUnpaid &&
        !(hasPendingGatewayPayments && canSync) &&
        !user.isOwner)
      return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.orange[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(LucideIcons.shieldAlert, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Área da Organização",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showPublish)
                ElevatedButton(
                  onPressed: () =>
                      service.updateEventStatus(event.id!, 'published'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("PUBLICAR LISTA"),
                ),
              if (showSort)
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeamSortingScreen(event: event),
                    ),
                  ),
                  icon: Icon(LucideIcons.shuffle, size: 16),
                  label: const Text("SORTEAR"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              if (showClose)
                ElevatedButton.icon(
                  onPressed: () {
                    if (unpaidTitularsCount > 0) {
                      _showLockedAlert(
                        "Não é possível encerrar o racha.\n\nAinda existem $unpaidTitularsCount atletas titulares com o pagamento pendente.\n\nResolva os pagamentos ou clique em 'REMOVER NÃO PAGOS' primeiro.",
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventClosingScreen(event: event),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(LucideIcons.lock, size: 16),
                  label: const Text("ENCERRAR"),
                ),
              if (showReopen)
                ElevatedButton.icon(
                  onPressed: widget.onReopen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(LucideIcons.rotateCcw, size: 16),
                  label: const Text("REABRIR"),
                ),
              if (showRemoveUnpaid)
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.isListLocked) {
                      _showLockedAlert(
                        "Níveis já definidos! Não é possível remover em massa.",
                      );
                      return;
                    }
                    _confirmRemoveUnpaid(service, unpaidTitularsCount);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(LucideIcons.userMinus, size: 16),
                  label: const Text("REMOVER NÃO PAGOS"),
                ),
              if (hasPendingGatewayPayments && canSync)
                ElevatedButton.icon(
                  onPressed: _isVerifyingPayments ? null : _forceSyncPayments,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                  ),
                  icon: _isVerifyingPayments
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text("SINCRONIZAR PAGAMENTOS"),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
