import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/finance_service.dart';
import '../../services/auth_service.dart';
import '../../models/transaction_model.dart';
import '../../models/user_model.dart';

class FinanceScreen extends StatefulWidget {
  final String groupId;

  const FinanceScreen({super.key, required this.groupId});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    // PADRÃO: HOJE
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  void _pickDateRange() async {
    final newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
      saveText: "FILTRAR",
      helpText: "Selecione o período",
      locale: const Locale('pt', 'BR'),
    );

    if (newRange != null) {
      setState(() {
        _dateRange = DateTimeRange(
          start: newRange.start,
          end: DateTime(
            newRange.end.year,
            newRange.end.month,
            newRange.end.day,
            23,
            59,
            59,
          ),
        );
      });
    }
  }

  void _showAddTransactionDialog(UserModel currentUser) {
    final descController = TextEditingController();
    final amountController = TextEditingController();
    String type = 'debit';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Novo Lançamento"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              items: const [
                DropdownMenuItem(
                  value: 'debit',
                  child: Text("🔴 Despesa (Saída)"),
                ),
                DropdownMenuItem(
                  value: 'credit',
                  child: Text("🟢 Receita (Entrada)"),
                ),
              ],
              onChanged: (v) => type = v!,
              decoration: const InputDecoration(labelText: "Tipo"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: "Descrição (Ex: Bola nova)",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "Valor (R\$)",
                prefixText: "R\$ ",
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
            onPressed: () {
              final amount = double.tryParse(
                amountController.text.replaceAll(',', '.'),
              );
              if (descController.text.isNotEmpty && amount != null) {
                Provider.of<FinanceService>(
                  context,
                  listen: false,
                ).addManualTransaction(
                  description: descController.text,
                  amount: amount,
                  type: type,
                  date: DateTime.now(),
                  registeredBy: currentUser,
                  groupId: widget.groupId,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text("SALVAR"),
          ),
        ],
      ),
    );
  }

  String _getPeriodText() {
    final start = _dateRange!.start;
    final end = _dateRange!.end;
    final now = DateTime.now();

    if (start.day == now.day &&
        start.month == now.month &&
        start.year == now.year &&
        end.day == now.day &&
        end.month == now.month &&
        end.year == now.year) {
      return "Movimentações de Hoje";
    }

    final f = DateFormat('dd/MM');
    return "${f.format(start)} até ${f.format(end)}";
  }

  @override
  Widget build(BuildContext context) {
    final financeService = Provider.of<FinanceService>(context, listen: false);
    final user = Provider.of<AuthService>(context).currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Acesso restrito.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Fluxo de Caixa", style: TextStyle(fontSize: 18)),
            Text(
              _getPeriodText(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.calendarRange),
            onPressed: _pickDateRange,
            tooltip: "Filtrar Período",
          ),
        ],
      ),

      // VALIDAR PERMISSÃO DE LANÇAMENTO
      floatingActionButton: widget.groupId.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddTransactionDialog(user),
              icon: Icon(LucideIcons.plus),
              label: const Text("LANÇAMENTO"),
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
            )
          : null,

      body: Column(
        children: [
          // 1. SALDO DO GRUPO ATUAL
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .where('group_id', isEqualTo: widget.groupId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Erro ao carregar o saldo: ${snapshot.error}'),
                );
              }
              double totalBalance = 0;
              if (snapshot.hasData) {
                final allDocs = snapshot.data!.docs;
                final allTrans = allDocs
                    .map(
                      (d) => TransactionModel.fromMap(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .toList();
                final totals = financeService.calculateTotals(allTrans);
                totalBalance = totals['balance']!;
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green[900]!.withOpacity(0.3)
                      : Colors.green[50],
                  border: Border(
                    bottom: BorderSide(color: Colors.green.withOpacity(0.3)),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      "SALDO DISPONÍVEL EM CAIXA",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.greenAccent : Colors.green[800],
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "R\$ ${totalBalance.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: totalBalance >= 0
                            ? (isDark ? Colors.white : Colors.black)
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. MOVIMENTAÇÃO DO PERÍODO
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: financeService.getTransactionsStream(
                widget.groupId,
                _dateRange!.start,
                _dateRange!.end,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(child: Text("Erro: ${snapshot.error}"));
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs;
                final transactions = docs
                    .map(
                      (d) => TransactionModel.fromMap(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .toList();
                final totals = financeService.calculateTotals(transactions);

                return Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              "RESUMO DO PERÍODO SELECIONADO",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildSummaryItem(
                                  "Entradas",
                                  totals['income']!,
                                  Colors.green,
                                ),
                                _buildSummaryItem(
                                  "Saídas",
                                  totals['expense']!,
                                  Colors.red,
                                ),
                                _buildSummaryItem(
                                  "Resultado",
                                  totals['balance']!,
                                  totals['balance']! >= 0
                                      ? (isDark ? Colors.white : Colors.black)
                                      : Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    if (transactions.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            "Nenhuma movimentação neste período.",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: transactions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = transactions[index];
                            final isCredit = t.type == 'credit';

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: isCredit
                                    ? Colors.green[100]
                                    : Colors.red[100],
                                child: Icon(
                                  isCredit
                                      ? LucideIcons.arrowUpCircle
                                      : LucideIcons.arrowDownCircle,
                                  color: isCredit ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                t.description,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    DateFormat('dd/MM HH:mm').format(t.date),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (t.registeredByName.isNotEmpty)
                                    Text(
                                      " • Por: ${t.registeredByName}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Text(
                                "${isCredit ? '+' : '-'} R\$ ${t.amount.toStringAsFixed(2)}",
                                style: TextStyle(
                                  color: isCredit
                                      ? Colors.green[800]
                                      : Colors.red[800],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          "R\$ ${value.toStringAsFixed(2)}",
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
