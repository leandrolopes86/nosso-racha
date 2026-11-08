import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import para Clipboard
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/user_service.dart';
import '../../models/user_model.dart';

class BirthdaysScreen extends StatefulWidget {
  final String? groupId;

  const BirthdaysScreen({super.key, this.groupId});

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    // Define datas padrão: Dia 01 até o Último dia do mês atual
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
  }

  // Selecionar Data
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 1),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  // Verifica se o aniversário cai no intervalo (Ignorando o ano de nascimento)
  bool _isBirthdayInPeriod(
    String birthDateString,
    DateTime start,
    DateTime end,
  ) {
    if (birthDateString.length < 10) return false;
    try {
      final birthDate = DateFormat('dd/MM/yyyy').parse(birthDateString);

      // Normaliza para o ano atual para comparação
      DateTime comparisonDate = DateTime(
        start.year,
        birthDate.month,
        birthDate.day,
      );

      // Ajuste para virada de ano
      if (comparisonDate.isBefore(
        DateTime(start.year, start.month, start.day),
      )) {
        comparisonDate = DateTime(
          start.year + 1,
          birthDate.month,
          birthDate.day,
        );
      }

      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day);

      if (e.year > s.year) {
        return comparisonDate.isAfter(s.subtract(const Duration(days: 1))) &&
            comparisonDate.isBefore(e.add(const Duration(days: 1)));
      }

      return comparisonDate.isAfter(s.subtract(const Duration(days: 1))) &&
          comparisonDate.isBefore(e.add(const Duration(days: 1)));
    } catch (e) {
      return false;
    }
  }

  // --- LÓGICA DE COMPARTILHAMENTO ATUALIZADA ---
  void _shareBirthdays(List<UserModel> users) {
    if (users.isEmpty) return;

    StringBuffer sb = StringBuffer();
    sb.writeln("🎂 *ANIVERSARIANTES* 🎂");
    sb.writeln(
      "De: ${DateFormat('dd/MM').format(_startDate)} até ${DateFormat('dd/MM').format(_endDate)}",
    );
    sb.writeln("");

    for (var u in users) {
      final String name = u.nickname.isNotEmpty ? u.nickname : u.name;
      final String dayMonth = u.birthDate.substring(0, 5);
      sb.writeln("🎉 $dayMonth - $name");
    }
    sb.writeln("\n_Gerado pelo App LCS_");

    final String textToShare = sb.toString();

    // Modal Padronizado (Mesmo estilo das outras telas)
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
                  Share.share(textToShare);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.copy),
                title: const Text("Copiar Texto"),
                subtitle: const Text("Para colar manualmente (WhatsApp Web)"),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: textToShare));
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

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text("Aniversariantes")),
      body: Column(
        children: [
          // --- FILTRO DE DATA ---
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, true),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Início",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Row(
                            children: [
                              Icon(LucideIcons.calendar, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('dd/MM/yyyy').format(_startDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Icon(LucideIcons.arrowRight, color: Colors.grey),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, false),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "Fim",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat('dd/MM/yyyy').format(_endDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(LucideIcons.calendar, size: 16),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- LISTA ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: userService.getAllAthletesStream(groupId: widget.groupId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Não foi possível carregar os aniversariantes: ${snapshot.error}',
                    ),
                  );
                }
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final allUsers = snapshot.data!.docs.map((doc) {
                  return UserModel.fromMap(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  );
                }).toList();

                // 1. Filtrar pela data
                final birthdays = allUsers.where((u) {
                  if (u.status == 'suspended') return false;
                  return _isBirthdayInPeriod(u.birthDate, _startDate, _endDate);
                }).toList();

                // 2. Ordenar por dia/mês
                birthdays.sort((a, b) {
                  try {
                    final dA = DateFormat('dd/MM/yyyy').parse(a.birthDate);
                    final dB = DateFormat('dd/MM/yyyy').parse(b.birthDate);
                    int cmp = dA.month.compareTo(dB.month);
                    if (cmp == 0) return dA.day.compareTo(dB.day);
                    return cmp;
                  } catch (e) {
                    return 0;
                  }
                });

                if (birthdays.isEmpty) {
                  return const Center(
                    child: Text("Nenhum aniversariante neste período."),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${birthdays.length} encontrados",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          // Botão com novo comportamento
                          TextButton.icon(
                            onPressed: () => _shareBirthdays(birthdays),
                            icon: Icon(LucideIcons.share2, size: 16),
                            label: const Text("Compartilhar"),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: birthdays.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final user = birthdays[index];
                          final dateParts = user.birthDate.split('/');
                          final dayMonth = dateParts.length >= 2
                              ? "${dateParts[0]}/${dateParts[1]}"
                              : user.birthDate;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.pink[50],
                              child: Icon(LucideIcons.cake, color: Colors.pink),
                            ),
                            title: Text(
                              user.nickname.isNotEmpty
                                  ? user.nickname
                                  : user.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(user.name),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.pink,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                dayMonth,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
            ),
          ),
        ],
      ),
    );
  }
}
