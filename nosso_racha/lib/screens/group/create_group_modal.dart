import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/auth_service.dart';

class CreateGroupModal extends StatefulWidget {
  const CreateGroupModal({super.key});

  @override
  State<CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<CreateGroupModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController(text: 'São Paulo');
  final _neighborhoodController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;

      if (user == null) throw Exception("Usuário não autenticado.");
      if (!user.canCreateOrganizations) {
        throw StateError(
          'A criação de organizações está disponível para organizadores.',
        );
      }

      final firestore = FirebaseFirestore.instance;
      final ownedGroups = await firestore
          .collection('groups')
          .where('owner_id', isEqualTo: user.uid)
          .get();
      final legacyOwnedGroups = await firestore
          .collection('groups')
          .where('ownerId', isEqualTo: user.uid)
          .get();
      final ownedGroupIds = <String>{
        ...ownedGroups.docs.map((group) => group.id),
        ...legacyOwnedGroups.docs.map((group) => group.id),
      };
      final maxGroups = user.planLimits.maxOwnedOrganizations;
      if (!user.isMaster &&
          maxGroups != null &&
          ownedGroupIds.length >= maxGroups) {
        throw StateError(
          'O limite de $maxGroups organização(ões) do seu plano foi atingido.',
        );
      }
      final groupRef = firestore.collection('groups').doc();
      final batch = firestore.batch();

      batch.set(groupRef, {
        'id': groupRef.id,
        'name': _nameController.text.trim(),
        'owner_id': user.uid,
        'owner_name': user.name,
        'city': _cityController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'open_events_count': 0,
        'athlete_count': 0,
        'co_organizer_count': 0,
      });
      batch.set(groupRef.collection('members').doc(user.uid), {
        'uid': user.uid,
        'role': 'owner',
        'joined_at': FieldValue.serverTimestamp(),
      });
      final userRef = firestore.collection('users').doc(user.uid);
      batch.update(userRef, {
        'group_ids': FieldValue.arrayUnion([groupRef.id]),
        'membership_change_group_id': groupRef.id,
        'membership_change_nonce': groupRef.id,
      });
      await batch.commit();

      await authService.reloadUser();

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, true); // Retorna true indicando sucesso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Grupo criado com sucesso!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erro ao criar grupo: ${e.toString().replaceFirst('Bad state: ', '')}",
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Criar Meu Grupo de Racha",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  "Como Organizador VIP, crie comunidades e gerencie seus eventos.",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Nome do Grupo *",
                    hintText: "Ex: Pelada dos Amigos Oficial",
                    prefixIcon: Icon(LucideIcons.users),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Informe o nome do grupo"
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _neighborhoodController,
                  decoration: const InputDecoration(
                    labelText: "Bairro Principal *",
                    hintText: "Ex: Jardins / Centro",
                    prefixIcon: Icon(LucideIcons.mapPin),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Informe o bairro"
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: "Cidade *",
                    prefixIcon: Icon(LucideIcons.building),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Informe a cidade"
                      : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "CRIAR GRUPO",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
