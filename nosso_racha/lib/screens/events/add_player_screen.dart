import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/user_service.dart';
import '../../services/event_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../admin/register_guest_screen.dart'; // <--- CORRIGIDO: Caminho correto da tela de registro

class AddPlayerScreen extends StatefulWidget {
  final String eventId;
  final List<String> existingParticipantIds;
  final bool selectOnly;

  const AddPlayerScreen({
    super.key,
    required this.eventId,
    required this.existingParticipantIds,
    this.selectOnly = false,
  });

  @override
  State<AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends State<AddPlayerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String text) {
    String str = text.toLowerCase();
    const withDia = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
    const withoutDia = 'aaaaaaeeeeiiiiooooouuuucn';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
  }

  // --- FORMATAÇÃO DA NOTA (OVR 1-99) ---
  String _formatRating(double rating) {
    // Se for 0 ou menor, exibe traço
    if (rating <= 0) return '-';

    // Apenas converte para inteiro, sem multiplicar.
    return rating.toInt().toString();
  }

  void _handleAddUser(UserModel user) {
    final eventService = widget.selectOnly
        ? null
        : Provider.of<EventService>(context, listen: false);

    bool isGoleiro = user.positions.contains('Goleiro');
    bool isLinha =
        user.positions.any((p) => p != 'Goleiro') || user.positions.isEmpty;

    if (isGoleiro && isLinha) {
      _showPositionDialog(context, eventService, user);
    } else if (isGoleiro) {
      _confirmAdd(eventService, user, 'goalkeeper');
    } else {
      _confirmAdd(eventService, user, 'line');
    }
  }

  Future<void> _confirmAdd(
      EventService? service, UserModel user, String role) async {
    // --- MODO SELEÇÃO (Para Avulsos no Fechamento) ---
    if (widget.selectOnly) {
      Navigator.pop(context, {'user': user, 'role': role});
      return;
    }

    // --- MODO PADRÃO (Salva no Banco) ---
    try {
      if (service != null) {
        await service.addPlayerToEvent(widget.eventId, user, role);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "${user.name} adicionado como ${role == 'goalkeeper' ? 'Goleiro' : 'Linha'}!"),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
          _searchController.clear();
          setState(() => _searchQuery = '');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erro ao adicionar: $e"),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPositionDialog(
      BuildContext context, EventService? service, UserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.selectOnly
            ? "Selecionar ${user.name}"
            : "Adicionar ${user.name}"),
        content: const Text(
            "Este atleta joga nas duas posições. Onde ele vai jogar hoje?"),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmAdd(service, user, 'goalkeeper');
            },
            icon: Icon(LucideIcons.shield, color: Colors.purple),
            label:
                const Text("GOLEIRO", style: TextStyle(color: Colors.purple)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmAdd(service, user, 'line');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            icon: Icon(LucideIcons.user),
            label: const Text("LINHA"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context, listen: false);
    final currentUser =
        Provider.of<AuthService>(context, listen: false).currentUser;

    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.selectOnly ? "Selecionar Avulso" : "Adicionar ao Jogo")),

      // --- NOVO: BOTÃO PARA CADASTRAR ATLETA ---
      floatingActionButton: (currentUser != null && currentUser.canRegisterUser)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterGuestScreen()));
              },
              icon: Icon(LucideIcons.userPlus),
              label: const Text("NOVO ATLETA"),
            )
          : null,

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: kIsWeb,
              decoration: InputDecoration(
                hintText: "Buscar atleta...",
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
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = _normalize(value);
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: userService.getAllAthletesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs;
                final allUsers = docs.map((doc) {
                  return UserModel.fromMap(
                      doc.id, doc.data() as Map<String, dynamic>);
                }).toList();

                final availableUsers = allUsers.where((u) {
                  if (u.status == 'suspended') return false;
                  if (widget.existingParticipantIds.contains(u.uid))
                    return false;

                  final nameNormalized = _normalize(u.name);
                  final nicknameNormalized = _normalize(u.nickname);

                  return nameNormalized.contains(_searchQuery) ||
                      nicknameNormalized.contains(_searchQuery);
                }).toList();

                if (availableUsers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _searchQuery.isEmpty
                                ? LucideIcons.userCheck
                                : LucideIcons.searchX,
                            size: 64,
                            color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                            _searchQuery.isEmpty
                                ? "Nenhum atleta disponível."
                                : "Nenhum atleta encontrado.",
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: availableUsers.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final user = availableUsers[index];
                    String position = user.positions.isNotEmpty
                        ? user.positions.join('/')
                        : 'Linha';
                    String rating = _formatRating(user.rating);
                    final bool isGK = user.positions.contains('Goleiro');

                    // Lógica para definir o destaque (Apelido em evidência, Nome completo abaixo)
                    final String displayNickname = user.nickname.isNotEmpty ? user.nickname : user.name;
                    final String displayFullName = user.name;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: user.status == 'active'
                            ? (isGK ? Colors.purple[100] : Colors.green[100])
                            : Colors.grey[300],
                        child: Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: isGK ? Colors.purple : Colors.green[800],
                                fontWeight: FontWeight.bold)),
                      ),
                      // TÍTULO: Apelido em destaque (Negrito)
                      title: Text(
                        displayNickname,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      // SUBTÍTULO: Linha 1 = Nome completo | Linha 2 = Posição e OVR
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (user.nickname.isNotEmpty) ...[
                            Text(
                              displayFullName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            "$position • OVR: $rating",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true, // Importante para acomodar as 3 linhas de texto sem cortar
                      trailing: Icon(
                          widget.selectOnly
                              ? LucideIcons.checkCircle
                              : LucideIcons.plusCircle,
                          color: widget.selectOnly ? Colors.blue : Colors.green),
                      onTap: () => _handleAddUser(user),
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
}
