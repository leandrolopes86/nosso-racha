import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import 'register_guest_screen.dart';
import 'birthdays_screen.dart';

class UserManagementScreen extends StatefulWidget {
  final String groupId;

  const UserManagementScreen({super.key, required this.groupId});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filtros e Ordenação
  String _selectedFilter = 'all';
  String _selectedSort = 'name';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- FORMATAÇÃO DA NOTA (OVR 1-99) ---
  String _formatRating(double rating) {
    // Se for 0 ou menor, exibe traço
    if (rating <= 0) return '-';

    return rating.toInt().toString();
  }

  // --- LÓGICA DE COMPARTILHAMENTO ---
  void _handleShare(List<UserModel> users) {
    if (users.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("A lista está vazia.")));
      return;
    }

    StringBuffer sb = StringBuffer();
    sb.writeln("*📋 RELAÇÃO DE ATLETAS - LCS*");

    // Adiciona info do filtro no cabeçalho
    String filtroTexto = _selectedFilter == 'all'
        ? "Todos"
        : (_selectedFilter == 'active'
              ? "Ativos"
              : (_selectedFilter == 'inactive' ? "Convidados" : "Suspensos"));
    sb.writeln("Filtro: $filtroTexto | Total: ${users.length}");
    sb.writeln("");

    for (var user in users) {
      // Prioriza Apelido. Se vazio, usa Nome.
      String nameDisplay = user.nickname.isNotEmpty ? user.nickname : user.name;

      String statusIcon = "";
      if (user.status == 'active')
        statusIcon = "✅";
      else if (user.status == 'inactive')
        statusIcon = "⚪";
      else if (user.status == 'suspended')
        statusIcon = "🚫";

      String pos = user.positions.isNotEmpty ? user.positions.first : "Linha";

      // Adiciona a nota formatada sem decimais
      String rating = _formatRating(user.rating);

      // Inclui última data no share se existir
      String lastGame = "";
      if (user.lastMatchDate != null) {
        lastGame =
            " | Último: ${DateFormat('dd/MM/yy').format(user.lastMatchDate!)}";
      }

      sb.writeln("$statusIcon $nameDisplay - $pos - Nota: $rating$lastGame");
    }

    sb.writeln("\n_Gerado pelo App LCS_");

    String textToShare = sb.toString();

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
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser!;

    return StreamBuilder<QuerySnapshot>(
      stream: userService.getAllAthletesStream(groupId: widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Meus Atletas')),
            body: Center(
              child: Text(
                'Não foi possível carregar os atletas: ${snapshot.error}',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text("Meus Atletas")),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs;

        final allUsers = docs.map((doc) {
          return UserModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }).toList();

        final int totalActive = allUsers
            .where((u) => u.status == 'active')
            .length;
        final int totalGuests = allUsers
            .where((u) => u.status == 'inactive')
            .length;
        final int totalSuspended = allUsers
            .where((u) => u.status == 'suspended')
            .length;

        var filteredUsers = allUsers.where((user) {
          if (_selectedFilter != 'all' && user.status != _selectedFilter) {
            return false;
          }
          final nameLower = user.name.toLowerCase();
          final nicknameLower = user.nickname.toLowerCase();
          return nameLower.contains(_searchQuery) ||
              nicknameLower.contains(_searchQuery);
        }).toList();

        filteredUsers.sort((a, b) {
          switch (_selectedSort) {
            case 'nickname':
              final nickA = a.nickname.isNotEmpty ? a.nickname : a.name;
              final nickB = b.nickname.isNotEmpty ? b.nickname : b.name;
              return nickA.toLowerCase().compareTo(nickB.toLowerCase());
            case 'rating':
              return b.rating.compareTo(a.rating);
            case 'rating_asc':
              return a.rating.compareTo(b.rating);
            case 'name':
            default:
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text("Meus Atletas"),
            actions: [
              // --- BOTÃO ANIVERSARIANTES ---
              IconButton(
                icon: Icon(LucideIcons.cake),
                tooltip: "Aniversariantes",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BirthdaysScreen(groupId: widget.groupId),
                    ),
                  );
                },
              ),
              // --- BOTÃO COMPARTILHAR ---
              if (currentUser.isMaster)
                IconButton(
                  icon: Icon(LucideIcons.share2),
                  tooltip: "Compartilhar Lista",
                  onPressed: () => _handleShare(filteredUsers),
                ),
            ],
          ),
          floatingActionButton: widget.groupId.isNotEmpty
              ? FloatingActionButton(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RegisterGuestScreen(groupId: widget.groupId),
                      ),
                    );
                  },
                  child: Icon(LucideIcons.userPlus),
                )
              : null,
          body: Column(
            children: [
              _buildSummaryHeader(totalActive, totalGuests, totalSuspended),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        value: _selectedFilter,
                        decoration: InputDecoration(
                          labelText: "Exibir",
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text("Todos")),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text("Ativos"),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text("Convidados"),
                          ),
                          DropdownMenuItem(
                            value: 'suspended',
                            child: Text("Suspensos"),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedFilter = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<String>(
                        value: _selectedSort,
                        decoration: InputDecoration(
                          labelText: "Ordenar por",
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'name',
                            child: Text("Nome (A-Z)"),
                          ),
                          DropdownMenuItem(
                            value: 'nickname',
                            child: Text("Apelido (A-Z)"),
                          ),
                          DropdownMenuItem(
                            value: 'rating',
                            child: Text("Nota (Maior)"),
                          ),
                          DropdownMenuItem(
                            value: 'rating_asc',
                            child: Text("Nota (Menor)"),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedSort = val!),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Buscar por nome ou apelido...",
                    prefixIcon: Icon(LucideIcons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
              ),
              Expanded(
                child: filteredUsers.isEmpty
                    ? const Center(child: Text("Nenhum atleta encontrado."))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final targetUser = filteredUsers[index];

                          final positions = targetUser.positions;
                          // Utiliza a função de formatação
                          final rating = _formatRating(targetUser.rating);

                          bool isTargetStaff = targetUser.role == 'org';
                          if (targetUser.role == 'master' &&
                              targetUser.positions.isEmpty)
                            isTargetStaff = true;

                          bool canEdit = false;
                          if (currentUser.isMaster) {
                            canEdit = true;
                          } else {
                            canEdit =
                                !targetUser.isMaster && !targetUser.isOwner;
                          }

                          // Texto do último jogo
                          String lastGameText = "Nunca jogou";
                          if (targetUser.lastMatchDate != null) {
                            lastGameText =
                                "Último: ${DateFormat('dd/MM/yyyy').format(targetUser.lastMatchDate!)}";
                          }

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: targetUser.status == 'active'
                                  ? Colors.green[100]
                                  : Colors.grey[300],
                              child: Text(
                                targetUser.name.isNotEmpty
                                    ? targetUser.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: targetUser.status == 'active'
                                      ? Colors.green[800]
                                      : Colors.grey[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: targetUser.nickname.isNotEmpty
                                      ? Text(
                                          "${targetUser.nickname}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : Text(
                                          targetUser.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                                if (targetUser.isOwner)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6.0),
                                    child: Icon(
                                      LucideIcons.crown,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                //if (targetUser.nickname.isNotEmpty)
                                Text(
                                  "(${targetUser.name})",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isTargetStaff
                                      ? "Organização / Staff • Nota: $rating"
                                      : "${positions.join(', ')} • Nota: $rating",
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  lastGameText,
                                  style: TextStyle(
                                    color: Colors.blueGrey[400],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (targetUser.status == 'inactive')
                                  const Chip(
                                    label: Text("Convidado"),
                                    backgroundColor: Colors.grey,
                                    labelStyle: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (targetUser.status == 'suspended')
                                  const Chip(
                                    label: Text("Suspenso"),
                                    backgroundColor: Colors.red,
                                    labelStyle: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                const SizedBox(width: 8),
                                if (canEdit)
                                  Icon(
                                    LucideIcons.pencil,
                                    size: 16,
                                    color: Colors.grey,
                                  )
                                else
                                  Icon(
                                    LucideIcons.lock,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                              ],
                            ),
                            onTap: canEdit
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RegisterGuestScreen(
                                          groupId: widget.groupId,
                                          userToEdit: targetUser,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- WIDGET DO RESUMO ---
  Widget _buildSummaryHeader(int active, int guests, int suspended) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          _buildCountCard("Ativos", active, Colors.green),
          const SizedBox(width: 8),
          _buildCountCard("Convidados", guests, Colors.grey),
          const SizedBox(width: 8),
          _buildCountCard("Suspensos", suspended, Colors.red),
        ],
      ),
    );
  }

  Widget _buildCountCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
