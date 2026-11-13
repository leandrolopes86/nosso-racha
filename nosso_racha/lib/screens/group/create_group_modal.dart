import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/auth_service.dart';

class _IBGEMunicipality {
  const _IBGEMunicipality({required this.name, required this.stateCode});

  final String name;
  final String stateCode;

  String get label => '$name - $stateCode';
}

String _normalizeCitySearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

class CreateGroupModal extends StatefulWidget {
  const CreateGroupModal({super.key});

  @override
  State<CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<CreateGroupModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  bool _isLoading = false;
  bool _isLoadingMunicipalities = true;
  String? _municipalityLoadError;
  List<_IBGEMunicipality> _municipalities = [];
  _IBGEMunicipality? _selectedMunicipality;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMunicipalities());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  Future<void> _loadMunicipalities() async {
    if (mounted) {
      setState(() {
        _isLoadingMunicipalities = true;
        _municipalityLoadError = null;
      });
    }

    try {
      final response = await http
          .get(
            Uri.https(
              'servicodados.ibge.gov.br',
              '/api/v1/localidades/municipios',
              {'orderBy': 'nome'},
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(
          'A API do IBGE respondeu com HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Resposta inválida da API do IBGE.');
      }

      final municipalities = decoded
          .map((entry) {
            if (entry is! Map<String, dynamic>) {
              throw const FormatException(
                'Município inválido na resposta do IBGE.',
              );
            }

            final immediateRegion =
                entry['regiao-imediata'] as Map<String, dynamic>?;
            final intermediaryRegion =
                immediateRegion?['regiao-intermediaria']
                    as Map<String, dynamic>?;
            final microregion = entry['microrregiao'] as Map<String, dynamic>?;
            final mesoregion =
                microregion?['mesorregiao'] as Map<String, dynamic>?;
            final state =
                (intermediaryRegion?['UF'] ?? mesoregion?['UF'])
                    as Map<String, dynamic>?;
            final name = entry['nome'];
            final stateCode = state?['sigla'];

            if (name is! String || stateCode is! String) {
              throw const FormatException(
                'Não foi possível identificar cidade e UF na resposta do IBGE.',
              );
            }
            return _IBGEMunicipality(name: name, stateCode: stateCode);
          })
          .toList(growable: false);

      if (mounted) setState(() => _municipalities = municipalities);
    } catch (error) {
      if (mounted) {
        setState(() {
          _municipalities = [];
          _municipalityLoadError = error is TimeoutException
              ? 'A consulta ao IBGE demorou demais. Verifique a conexão e tente novamente.'
              : 'Não foi possível carregar as cidades do IBGE: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingMunicipalities = false);
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    final municipality = _selectedMunicipality;
    if (municipality == null) return;

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
        'city': municipality.label,
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
                FormField<_IBGEMunicipality>(
                  validator: (value) => value == null
                      ? 'Selecione uma cidade da lista do IBGE'
                      : null,
                  builder: (fieldState) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Autocomplete<_IBGEMunicipality>(
                        displayStringForOption: (option) => option.label,
                        optionsBuilder: (textEditingValue) {
                          final query = _normalizeCitySearch(
                            textEditingValue.text.trim(),
                          );
                          if (query.isEmpty ||
                              _isLoadingMunicipalities ||
                              _municipalities.isEmpty) {
                            return const Iterable<_IBGEMunicipality>.empty();
                          }
                          return _municipalities
                              .where(
                                (city) => _normalizeCitySearch(
                                  city.label,
                                ).contains(query),
                              )
                              .take(30);
                        },
                        onSelected: (municipality) {
                          _selectedMunicipality = municipality;
                          fieldState.didChange(municipality);
                        },
                        optionsViewBuilder: (context, onSelected, options) =>
                            Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 240,
                                    maxWidth: 370,
                                  ),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option.label),
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                        fieldViewBuilder:
                            (
                              context,
                              textController,
                              focusNode,
                              onFieldSubmitted,
                            ) => TextFormField(
                              controller: textController,
                              focusNode: focusNode,
                              readOnly:
                                  _isLoadingMunicipalities ||
                                  _municipalities.isEmpty,
                              decoration: InputDecoration(
                                labelText: 'Cidade *',
                                hintText: _isLoadingMunicipalities
                                    ? 'Carregando municípios do IBGE…'
                                    : 'Digite o nome da cidade',
                                prefixIcon: const Icon(LucideIcons.building),
                                suffixIcon: _isLoadingMunicipalities
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                                border: const OutlineInputBorder(),
                                errorText: fieldState.errorText,
                              ),
                              onChanged: (value) {
                                if (_selectedMunicipality != null) {
                                  _selectedMunicipality = null;
                                  fieldState.didChange(null);
                                }
                              },
                            ),
                      ),
                      if (_municipalityLoadError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _municipalityLoadError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _isLoadingMunicipalities
                                ? null
                                : () => unawaited(_loadMunicipalities()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                        ),
                      ],
                    ],
                  ),
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
