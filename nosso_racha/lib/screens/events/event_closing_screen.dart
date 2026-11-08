import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import '../../models/participant_model.dart';
import '../../models/user_model.dart';
import '../../services/event_service.dart';
import '../../services/auth_service.dart';
import 'add_player_screen.dart';

class EventClosingScreen extends StatefulWidget {
  final EventModel event;

  const EventClosingScreen({super.key, required this.event});

  @override
  State<EventClosingScreen> createState() => _EventClosingScreenState();
}

class _EventClosingScreenState extends State<EventClosingScreen> {
  late List<ParticipantModel> _participants;

  late Set<String> _originalActiveIds;
  late Set<String> _originalTitularIds;

  @override
  void initState() {
    super.initState();
    _participants = List.from(widget.event.participants);

    _originalActiveIds = {};
    _originalTitularIds = {};

    int gkCount = 0;
    int lineCount = 0;
    int maxGk = widget.event.maxGoalkeepers;
    int maxLine = widget.event.maxLinePlayers;

    // 1. Identifica exatamente quem era Ativo e quem era Titular ANTES de mexer
    for (var p in _participants) {
      // Ignora completamente quem for isAvulso na contagem de vagas.
      if (p.status == 'active' && !p.isAvulso) {
        _originalActiveIds.add(p.uid);

        bool isTitular = false;
        if (p.roleInMatch == 'goalkeeper') {
          if (gkCount < maxGk) {
            isTitular = true;
            gkCount++;
          }
        } else {
          if (lineCount < maxLine) {
            isTitular = true;
            lineCount++;
          }
        }

        if (isTitular) {
          _originalTitularIds.add(p.uid);
        }
      }
    }

    // 2. Configura a presença inicial
    for (int i = 0; i < _participants.length; i++) {
      final p = _participants[i];

      if (p.status != 'active') {
        if (p.attendance != 'substitute') {
          _participants[i] = p.copyWith(attendance: 'substitute');
        }
        continue;
      }

      if (p.attendance == 'present' || p.attendance == 'absent') {
        continue;
      }

      if (_originalTitularIds.contains(p.uid) || p.isAvulso) {
        _participants[i] = p.copyWith(attendance: 'present');
      } else {
        _participants[i] = p.copyWith(attendance: 'substitute');
      }
    }
  }

  void _toggleAttendance(int index) {
    setState(() {
      final p = _participants[index];
      final newStatus = p.attendance == 'present' ? 'absent' : 'present';
      _participants[index] = p.copyWith(attendance: newStatus);
    });
  }

  void _removeFromCall(int index) {
    setState(() {
      final p = _participants[index];
      if (p.isAvulso) {
        _participants.removeAt(index);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Avulso removido.")));
      } else {
        _participants[index] = p.copyWith(attendance: 'substitute');
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Voltou para lista de espera.")));
      }
    });
  }

  Future<void> _addAvulso() async {
    final visibleIds = _participants
        .where((p) => p.attendance == 'present' || p.attendance == 'absent')
        .map((p) => p.uid)
        .toList();

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AddPlayerScreen(
                  eventId: widget.event.id!,
                  existingParticipantIds: visibleIds,
                  selectOnly: true,
                )));

    if (result != null && result is Map) {
      final UserModel user = result['user'];
      final String role = result['role'];

      setState(() {
        final existingIndex =
            _participants.indexWhere((p) => p.uid == user.uid);

        final bool wasOriginalActive = _originalActiveIds.contains(user.uid);

        if (existingIndex >= 0) {
          final existingP = _participants[existingIndex];

          _participants[existingIndex] = ParticipantModel(
            uid: existingP.uid,
            name: existingP.name,
            nickname: existingP.nickname,
            status: 'active',
            registeredAt: existingP.registeredAt,
            roleInMatch: role,
            // CORREÇÃO: Mantém o status original de pagamento. Não força mais o "pago".
            paymentStatus: existingP.paymentStatus,
            paymentGatewayId: existingP.paymentGatewayId,
            isStaff: existingP.isStaff,
            isGuest: existingP.isGuest,
            attendance: 'present',
            isAvulso: !wasOriginalActive,
          );

          String tipo = wasOriginalActive
              ? "Suplente convocado"
              : "Readicionado como Avulso";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("${user.name} adicionado! ($tipo)"),
              backgroundColor: Colors.green));
        } else {
          final newParticipant = ParticipantModel(
              uid: user.uid,
              name: user.name,
              nickname: user.nickname,
              status: 'active',
              roleInMatch: role,
              registeredAt: DateTime.now(),
              // CORREÇÃO: Avulsos novos entram como PENDENTES. Não altera finanças de quem é fora da lista.
              paymentStatus: 'pending',
              isGuest: user.status == 'inactive',
              isStaff: false,
              attendance: 'present',
              isAvulso: true,
              paymentGatewayId: null);
          _participants.add(newParticipant);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("${user.name} adicionado como Avulso!"),
              backgroundColor: Colors.blue));
        }
      });
    }
  }

  String _generateClosingReport() {
    StringBuffer sb = StringBuffer();
    sb.writeln("*📋 SÚMULA FINAL - ${widget.event.title.toUpperCase()}*");
    sb.writeln(
        "📅 Data: ${DateFormat('dd/MM/yyyy').format(widget.event.startDateTime)}");
    sb.writeln("");

    final presentes =
        _participants.where((p) => p.attendance == 'present').toList();
    final faltas =
        _participants.where((p) => p.attendance == 'absent').toList();

    sb.writeln("*✅ PRESENTES (${presentes.length})*");
    for (var p in presentes) {
      String name = p.nickname.isNotEmpty ? p.nickname : p.name;
      String extra = p.isAvulso ? " (Avulso)" : "";
      if (!p.isAvulso && !_originalTitularIds.contains(p.uid)) {
        extra = " (Suplente)";
      }
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

  void _showClosingReport() {
    final report = _generateClosingReport();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Súmula do Jogo"),
        content: SingleChildScrollView(
          child: SelectableText(report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Copiado para a área de transferência!"),
                  backgroundColor: Colors.green));
              Navigator.pop(ctx);
            },
            icon: Icon(LucideIcons.copy),
            label: const Text("COPIAR"),
          ),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("FECHAR"))
        ],
      ),
    );
  }

  Future<void> _submit() async {
    bool hasUnpaid = false;
    for (var p in _participants) {
      if ((p.attendance == 'present' || p.attendance == 'absent') &&
          _originalTitularIds.contains(p.uid) &&
          p.roleInMatch != 'goalkeeper' &&
          p.paymentStatus != 'paid') {
        hasUnpaid = true;
        break;
      }
    }

    if (hasUnpaid) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Pagamentos Pendentes"),
          content: const Text(
            "Há titulares originais na lista de chamada com pagamento pendente.\nValide ou remova-os da chamada antes de encerrar.",
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
          ],
        ),
      );
      return;
    }

    final eventService = Provider.of<EventService>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Encerrar Evento?"),
        content: const Text(
            "Isso salvará a lista de presença e atualizará estatísticas."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("CANCELAR")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("CONFIRMAR")),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await eventService.finalizeEvent(widget.event.id!, _participants);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Evento Finalizado com Sucesso!")));
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erro: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthService>(context).currentUser;
    final canAddGuest = currentUser != null && currentUser.canAddGuestPlayer;

    final displayIndices = <int>[];
    for (int i = 0; i < _participants.length; i++) {
      final p = _participants[i];
      if (p.status == 'active' &&
          (p.attendance == 'present' || p.attendance == 'absent')) {
        displayIndices.add(i);
      }
    }

    displayIndices.sort((a, b) {
      final pA = _participants[a];
      final pB = _participants[b];
      if (pA.roleInMatch == 'goalkeeper' && pB.roleInMatch != 'goalkeeper')
        return -1;
      if (pA.roleInMatch != 'goalkeeper' && pB.roleInMatch == 'goalkeeper')
        return 1;
      return pA.name.compareTo(pB.name);
    });

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chamada Final"),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.clipboardCheck),
            tooltip: "Ver Súmula",
            onPressed: _showClosingReport,
          ),
          if (canAddGuest)
            IconButton(
              icon: Icon(LucideIcons.userPlus),
              tooltip: "Adicionar Jogador (Avulso/Suplente)",
              onPressed: _addAvulso,
            )
        ],
      ),
      body: Column(
        children: [
          Container(
              padding: const EdgeInsets.all(16),
              color: Colors.amber[50],
              child: const Row(children: [
                Icon(LucideIcons.alertTriangle, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        "Confirme quem JOGOU.\nUse (+) para adicionar suplentes/avulsos.",
                        style: TextStyle(color: Colors.brown, fontSize: 13)))
              ])),
          Expanded(
            child: displayIndices.isEmpty
                ? const Center(child: Text("Nenhum jogador na chamada."))
                : ListView.separated(
                    itemCount: displayIndices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final realIndex = displayIndices[i];
                      final p = _participants[realIndex];
                      final isPresent = p.attendance == 'present';
                      final displayName =
                          p.nickname.isNotEmpty ? p.nickname : p.name;

                      final bool isOriginalTitular =
                          _originalTitularIds.contains(p.uid);

                      if (!isOriginalTitular) {
                        return ListTile(
                          leading: CircleAvatar(
                              backgroundColor: Colors.blue[100],
                              child:
                                  Icon(LucideIcons.plus, color: Colors.blue)),
                          title: Text(displayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue)),
                          subtitle: Text(
                              p.isAvulso ? "Avulso" : "Suplente Convocado",
                              style: const TextStyle(
                                  color: Colors.blueGrey, fontSize: 12)),
                          trailing: IconButton(
                            icon: Icon(LucideIcons.trash2, color: Colors.red),
                            onPressed: () => _removeFromCall(realIndex),
                            tooltip: "Remover da chamada",
                          ),
                        );
                      } else {
                        return SwitchListTile(
                            title: Text(displayName,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: isPresent
                                        ? null
                                        : TextDecoration.lineThrough,
                                    color:
                                        isPresent ? Colors.black : Colors.red)),
                            subtitle: Text(
                                "${p.roleInMatch == 'goalkeeper' ? 'Goleiro' : 'Linha'} ${p.paymentStatus == 'paid' ? '• Pago' : '• Pendente'}",
                                style: TextStyle(
                                    color: p.paymentStatus == 'paid'
                                        ? Colors.green[700]
                                        : Colors.orange[800])),
                            secondary: CircleAvatar(
                                backgroundColor:
                                    isPresent ? Colors.green : Colors.red[100],
                                child: Icon(
                                    isPresent
                                        ? LucideIcons.check
                                        : LucideIcons.x,
                                    color:
                                        isPresent ? Colors.white : Colors.red)),
                            value: isPresent,
                            activeThumbColor: Colors.green,
                            onChanged: (val) => _toggleAttendance(realIndex));
                      }
                    }),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(
                  color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))
            ]),
            child: Consumer<EventService>(builder: (context, service, _) {
              return ElevatedButton.icon(
                  onPressed: service.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white),
                  icon: service.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Icon(LucideIcons.lock),
                  label: const Text("ENCERRAR EVENTO"));
            }),
          )
        ],
      ),
    );
  }
}
