import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../models/event_model.dart';

class FinancialSummaryModal extends StatelessWidget {
  final EventModel event;

  const FinancialSummaryModal({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    // CORREÇÃO CRÍTICA: Usa a lista de fechamento caso o evento esteja finalizado (para incluir os avulsos no cálculo)
    final listToUse = event.status == 'finished' && event.closingList.isNotEmpty
        ? event.closingList
        : event.participants;
    final paidParticipants =
        listToUse.where((p) => p.paymentStatus == 'paid').toList();
    final totalExpected = paidParticipants.length * event.price;
    final totalCount = paidParticipants.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // --- CABEÇALHO ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(LucideIcons.wallet, color: Colors.green),
                    SizedBox(width: 8),
                    Text("Resumo Financeiro",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),

          // --- CARD DE RESUMO GERAL ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total Arrecadado",
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        NumberFormat.simpleCurrency(locale: 'pt_BR')
                            .format(totalExpected),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text("$totalCount Pagantes",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("DETALHAMENTO POR RESPONSÁVEL",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey))),
          ),
          const Divider(),

          // --- LISTA DETALHADA ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('related_event_id', isEqualTo: event.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  if (totalExpected > 0) {
                    return _buildLegacyList(totalExpected, totalCount);
                  }
                  return const Center(
                      child:
                          Text("Nenhuma movimentação financeira registrada."));
                }

                // 1. AGRUPAR TRANSAÇÕES POR ATLETA (Para calcular saldo individual)
                Map<String, List<Map<String, dynamic>>> userTransactions = {};

                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final userId = data['related_user_id'] ?? 'unknown';
                  if (!userTransactions.containsKey(userId)) {
                    userTransactions[userId] = [];
                  }
                  userTransactions[userId]!.add(data);
                }

                // 2. CALCULAR SALDOS E ATRIBUIR RESPONSÁVEL
                Map<String, _CollectorStats> collectors = {};
                double totalCalculatedFromLogs = 0;

                userTransactions.forEach((userId, logs) {
                  double balance = 0;
                  Map<String, dynamic>? activeCreditLog;

                  // Calcula o saldo do usuário (Créditos - Débitos)
                  for (var log in logs) {
                    final double amount = (log['amount'] as num).toDouble();
                    if (log['type'] == 'debit') {
                      balance -= amount;
                    } else {
                      balance += amount;
                      activeCreditLog =
                          log; // Guarda o log de crédito para saber quem recebeu
                    }
                  }

                  // Se o saldo final do usuário for positivo (ele pagou e não estornou)
                  // Contamos para o responsável pelo crédito.
                  // Se for 0 (pagou e estornou), ignoramos ele completamente (assim o estorno "anula" o recebimento visualmente).
                  if (balance > 0.01 && activeCreditLog != null) {
                    final String method =
                        activeCreditLog['payment_gateway_id'] != null
                            ? 'MP'
                            : 'MANUAL';
                    final String responsible = method == 'MP'
                        ? 'Automático (Mercado Pago)'
                        : (activeCreditLog['registered_by_name'] ??
                            'Admin Desconhecido');

                    if (!collectors.containsKey(responsible)) {
                      collectors[responsible] = _CollectorStats(
                          name: responsible,
                          isAuto: method == 'MP',
                          total: 0,
                          count: 0);
                    }
                    collectors[responsible]!.total += balance;
                    collectors[responsible]!.count += 1;
                    totalCalculatedFromLogs += balance;
                  }
                });

                // 3. TRATAMENTO DE LEGADO (Diferença entre Lista de Participantes e Logs)
                if (totalExpected > (totalCalculatedFromLogs + 0.01)) {
                  double diffValue = totalExpected - totalCalculatedFromLogs;
                  int diffCount =
                      (diffValue / (event.price > 0 ? event.price : 1)).round();

                  if (diffValue > 0) {
                    collectors['Legado'] = _CollectorStats(
                        name: 'Manual (Sem registro de log)',
                        isAuto: false,
                        total: diffValue,
                        count: diffCount,
                        isLegacy: true);
                  }
                }

                final sortedList = collectors.values.toList()
                  ..sort((a, b) => b.total.compareTo(a.total));

                if (sortedList.isEmpty) {
                  return const Center(
                      child: Text("Nenhum saldo positivo encontrado."));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedList.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final stat = sortedList[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: stat.isAuto
                            ? Colors.blue[100]
                            : (stat.isLegacy
                                ? Colors.grey[200]
                                : Colors.orange[100]),
                        child: Icon(
                            stat.isAuto
                                ? LucideIcons.zap
                                : (stat.isLegacy
                                    ? LucideIcons.history
                                    : LucideIcons.userCheck),
                            color: stat.isAuto
                                ? Colors.blue
                                : (stat.isLegacy ? Colors.grey : Colors.orange),
                            size: 20),
                      ),
                      title: Text(stat.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text("${stat.count} pagamentos ativos"),
                      trailing: Text(
                        NumberFormat.simpleCurrency(locale: 'pt_BR')
                            .format(stat.total),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyList(double total, int count) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            child: Icon(LucideIcons.history, color: Colors.grey, size: 20),
          ),
          title: const Text("Manual (Sem registro de log)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text("$count pagamentos recebidos"),
          trailing: Text(
            NumberFormat.simpleCurrency(locale: 'pt_BR').format(total),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
          ),
        )
      ],
    );
  }
}

class _CollectorStats {
  String name;
  bool isAuto;
  bool isLegacy;
  double total;
  int count;

  _CollectorStats(
      {required this.name,
      required this.isAuto,
      required this.total,
      required this.count,
      this.isLegacy = false});
}
