import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';

class ReportsScreen extends StatefulWidget {
  final String groupId;

  const ReportsScreen({super.key, required this.groupId});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedPeriodId;
  String _selectedPeriodName = "Atual (Em Aberto)";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showClosePeriodDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Fechar Ciclo de Estatísticas"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Isso irá salvar no histórico os resultados deste grupo e iniciar um novo ciclo. As estatísticas de outros grupos não serão alteradas.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: "Nome do Período (Ex: 2024 - 1º Semestre)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await Provider.of<UserService>(
                  context,
                  listen: false,
                ).closePeriod(titleController.text, groupId: widget.groupId);
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Período fechado e novo ciclo iniciado!"),
                    ),
                  );
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("Erro: $e")));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("FECHAR E ZERAR"),
          ),
        ],
      ),
    );
  }

  // --- NOVO: Stream Inteligente para Contar Rachas do Ciclo Atual ---
  Widget _buildCurrentCycleTotalStream() {
    return StreamBuilder<QuerySnapshot>(
      // 1. Busca o último fechamento para saber a data de corte
      stream: FirebaseFirestore.instance
          .collection('closings')
          .where('group_id', isEqualTo: widget.groupId)
          .orderBy('closed_at', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, closingSnap) {
        if (closingSnap.hasError) {
          return Center(
            child: Text(
              'Não foi possível carregar os fechamentos: ${closingSnap.error}',
            ),
          );
        }
        // Data de corte padrão (início dos tempos se não houver fechamento)
        DateTime? cutoffDate;

        if (closingSnap.hasData && closingSnap.data!.docs.isNotEmpty) {
          final data =
              closingSnap.data!.docs.first.data() as Map<String, dynamic>;
          if (data['closed_at'] != null) {
            cutoffDate = (data['closed_at'] as Timestamp).toDate();
          }
        }
        final cutoff = cutoffDate;

        // 2. Consulta os eventos finalizados APÓS a data de corte
        final eventsQuery = FirebaseFirestore.instance
            .collection('events')
            .where(
              Filter.or(
                Filter('info.group_id', isEqualTo: widget.groupId),
                Filter('group_id', isEqualTo: widget.groupId),
              ),
            );

        return StreamBuilder<QuerySnapshot>(
          stream: eventsQuery.snapshots(),
          builder: (context, eventsSnap) {
            if (eventsSnap.hasError) {
              return Center(
                child: Text(
                  'Não foi possível carregar os eventos do grupo: ${eventsSnap.error}',
                ),
              );
            }
            final int total =
                eventsSnap.data?.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final info = data['info'] as Map<String, dynamic>? ?? {};
                  final status = info['status'] ?? data['status'];
                  final startDate = info['start_date_time'];
                  final startsAfterCutoff =
                      cutoff == null ||
                      (startDate is Timestamp &&
                          startDate.toDate().isAfter(cutoff));
                  return status == 'finished' && startsAfterCutoff;
                }).length ??
                0;

            return _ReportList(
              groupId: widget.groupId,
              sortField: 'matchesPlayed',
              emptyMsg: "Nenhum atleta ativo.",
              periodId: null,
              periodName: _selectedPeriodName,
              totalMatches: total, // Passa o total calculado corretamente
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);
    // final eventService = Provider.of<EventService>(context, listen: false); // Removido pois usamos lógica local
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Relatórios", style: TextStyle(fontSize: 16)),
            StreamBuilder<QuerySnapshot>(
              stream: userService.getClosingsStream(groupId: widget.groupId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final closings = snapshot.data!.docs;
                return DropdownButton<String?>(
                  value: _selectedPeriodId,
                  dropdownColor: Theme.of(context).primaryColor,
                  icon: Icon(
                    LucideIcons.chevronDown,
                    color: Colors.white70,
                    size: 16,
                  ),
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text("Atual (Em Aberto)"),
                    ),
                    ...closings.map(
                      (doc) => DropdownMenuItem(
                        value: doc.id,
                        child: Text((doc.data() as Map)['title'] ?? 'Sem nome'),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedPeriodId = val;
                      if (val == null) {
                        _selectedPeriodName = "Atual (Em Aberto)";
                      } else {
                        final doc = closings.firstWhere((d) => d.id == val);
                        _selectedPeriodName = (doc.data() as Map)['title'];
                      }
                    });
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          if (_selectedPeriodId == null)
            IconButton(
              icon: Icon(LucideIcons.archive),
              tooltip: "Fechar Ciclo/Período",
              onPressed: _showClosePeriodDialog,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Assiduidade", icon: Icon(LucideIcons.medal)),
            Tab(text: "Faltas", icon: Icon(LucideIcons.thumbsDown)),
            Tab(text: "Inadimpl.", icon: Icon(LucideIcons.circleDollarSign)),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ABA ASSIDUIDADE: Lógica atualizada
          _selectedPeriodId == null
              ? _buildCurrentCycleTotalStream() // Usa a nova lógica para o ciclo atual
              : _ReportList(
                  groupId: widget.groupId,
                  sortField: 'matchesPlayed',
                  emptyMsg: "Nenhum atleta ativo.",
                  periodId: _selectedPeriodId,
                  periodName: _selectedPeriodName,
                ),

          _ReportList(
            groupId: widget.groupId,
            sortField: 'noShows',
            emptyMsg: "Nenhuma falta.",
            periodId: _selectedPeriodId,
            periodName: _selectedPeriodName,
          ),
          _ReportList(
            groupId: widget.groupId,
            sortField: 'unpaidRemovals',
            emptyMsg: "Nenhum inadimplente.",
            periodId: _selectedPeriodId,
            periodName: _selectedPeriodName,
          ),
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final String groupId;
  final String sortField;
  final String emptyMsg;
  final String? periodId;
  final String periodName;
  final int? totalMatches; // Novo parâmetro opcional

  const _ReportList({
    required this.groupId,
    required this.sortField,
    required this.emptyMsg,
    required this.periodId,
    required this.periodName,
    this.totalMatches,
  });

  Future<void> _shareList(BuildContext context, List<UserModel> users) async {
    String title = "";
    if (sortField == 'matchesPlayed') {
      title = "ASSIDUIDADE";
    } else if (sortField == 'noShows')
      title = "FALTAS";
    else
      title = "INADIMPLÊNCIA";

    StringBuffer sb = StringBuffer();
    sb.writeln("*📊 RELATÓRIO LCS: $title*");
    sb.writeln("📅 Período: $periodName");

    // Adiciona o total no compartilhamento se existir e for a aba de assiduidade
    if (sortField == 'matchesPlayed' && totalMatches != null) {
      sb.writeln("⚽ Total de Rachas Realizados: *$totalMatches*");
    }

    sb.writeln("");

    for (int i = 0; i < users.length; i++) {
      final u = users[i];
      int value = 0;
      if (sortField == 'matchesPlayed') {
        value = u.matchesPlayed;
      } else if (sortField == 'noShows')
        value = u.noShows;
      else if (sortField == 'unpaidRemovals')
        value = u.unpaidRemovals;

      String nameDisplay = u.nickname.isNotEmpty ? u.nickname : u.name;

      // Marca convidados no compartilhamento com (C)
      String guestMark = u.status == 'inactive' ? " (C)" : "";

      sb.writeln("${i + 1}. $nameDisplay$guestMark: *$value*");
    }
    sb.writeln("\n_Gerado pelo App LCS_");

    final text = sb.toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Compartilhar Relatório",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.share2),
              title: const Text("Compartilhar via..."),
              subtitle: const Text("WhatsApp, Telegram, etc."),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(text);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.copy),
              title: const Text("Copiar Texto"),
              subtitle: const Text("Para colar manualmente"),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: text));
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);

    Future<List<UserModel>> loadData() {
      if (periodId == null) {
        return userService.getGroupReportData(groupId);
      } else {
        return userService.getClosedPeriodData(periodId!);
      }
    }

    return FutureBuilder<List<UserModel>>(
      future: loadData(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Não foi possível carregar o relatório: ${snapshot.error}',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return Center(child: Text(emptyMsg));

        List<UserModel> users = snapshot.data!;

        users.sort((a, b) {
          int valA = 0;
          int valB = 0;
          if (sortField == 'matchesPlayed') {
            valA = a.matchesPlayed;
            valB = b.matchesPlayed;
          } else if (sortField == 'noShows') {
            valA = a.noShows;
            valB = b.noShows;
          } else if (sortField == 'unpaidRemovals') {
            valA = a.unpaidRemovals;
            valB = b.unpaidRemovals;
          }

          // Critério de desempate: Ativo primeiro, depois Convidado
          if (valA == valB) {
            if (a.status == 'active' && b.status != 'active') return -1;
            if (a.status != 'active' && b.status == 'active') return 1;
            return a.name.compareTo(b.name);
          }
          return valB.compareTo(valA);
        });

        users = users.where((u) {
          if (sortField == 'matchesPlayed') {
            return u.status != 'suspended';
          }
          if (sortField == 'noShows') return u.noShows > 0;
          if (sortField == 'unpaidRemovals') return u.unpaidRemovals > 0;
          return false;
        }).toList();

        if (users.isEmpty) return Center(child: Text(emptyMsg));

        return Column(
          children: [
            // --- CABEÇALHO DO TOTAL (SE APLICÁVEL) ---
            if (sortField == 'matchesPlayed' && totalMatches != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                color: Colors.green.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.trophy, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      "TOTAL DE RACHAS: $totalMatches",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _shareList(context, users),
                icon: Icon(LucideIcons.share2, size: 16),
                label: const Text("Exportar esta lista"),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final user = users[index];
                  int value = 0;
                  Color badgeColor = Colors.grey;

                  if (sortField == 'matchesPlayed') {
                    value = user.matchesPlayed;
                    badgeColor = Colors.blue;
                  } else if (sortField == 'noShows') {
                    value = user.noShows;
                    badgeColor = Colors.red;
                  } else if (sortField == 'unpaidRemovals') {
                    value = user.unpaidRemovals;
                    badgeColor = Colors.orange;
                  }

                  final displayName = user.nickname.isNotEmpty
                      ? user.nickname
                      : user.name;
                  final bool isGuest =
                      user.status == 'inactive'; // Identifica convidado

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: index < 3
                          ? Colors.amber[100]
                          : Colors.grey[200],
                      child: Text(
                        "${index + 1}º",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? Colors.amber[800] : Colors.black,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // --- TAG VISUAL DE CONVIDADO (Aumentada e Destacada) ---
                        if (isGuest)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "Convidado",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: null,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "$value",
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
