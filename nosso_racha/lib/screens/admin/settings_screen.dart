import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/settings_service.dart';
import 'payment_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String groupId;

  const SettingsScreen({super.key, required this.groupId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();

  bool _isEditingProfile = false;
  bool _isEditingPreferences = false;
  bool _includeGoalkeepers = false;
  bool _considerPositions = false;
  bool _isSavingProfile = false;
  bool _isSavingPreferences = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  void _syncProfileFields(Map<String, dynamic> group) {
    if (_isEditingProfile) return;
    _nameController.text = group['name'] as String? ?? '';
    _cityController.text = group['city'] as String? ?? '';
    _neighborhoodController.text = group['neighborhood'] as String? ?? '';
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _saveGroupProfile(SettingsService settingsService) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Informe o nome do grupo.', isError: true);
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      await settingsService.saveGroupProfile(
        groupId: widget.groupId,
        name: name,
        city: _cityController.text.trim(),
        neighborhood: _neighborhoodController.text.trim(),
      );
      if (mounted) {
        setState(() => _isEditingProfile = false);
        _showMessage('Dados do grupo salvos.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Erro ao salvar dados do grupo: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _savePreferences(SettingsService settingsService) async {
    setState(() => _isSavingPreferences = true);
    try {
      await settingsService.saveGroupSettings(
        groupId: widget.groupId,
        includeGoalkeepers: _includeGoalkeepers,
        considerPositions: _considerPositions,
      );
      if (mounted) {
        setState(() => _isEditingPreferences = false);
        _showMessage('Configurações do grupo salvas.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Erro ao salvar configurações: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingPreferences = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = context.read<SettingsService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do Grupo')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: settingsService.getGroupStream(widget.groupId),
        builder: (context, groupSnapshot) {
          if (groupSnapshot.hasError) {
            return Center(
              child: Text(
                'Não foi possível carregar os dados do grupo: '
                '${groupSnapshot.error}',
              ),
            );
          }
          if (!groupSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final group = groupSnapshot.data!.data();
          if (group == null) {
            return const Center(child: Text('O grupo não foi encontrado.'));
          }
          _syncProfileFields(group);

          return StreamBuilder<DocumentSnapshot>(
            stream: settingsService.getGroupSettingsStream(widget.groupId),
            builder: (context, settingsSnapshot) {
              if (settingsSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Não foi possível carregar as configurações: '
                    '${settingsSnapshot.error}',
                  ),
                );
              }
              if (!settingsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final settings =
                  settingsSnapshot.data!.data() as Map<String, dynamic>? ??
                  const {};
              if (!_isEditingPreferences) {
                _includeGoalkeepers =
                    settings['default_include_goalkeepers'] as bool? ?? false;
                _considerPositions =
                    settings['default_consider_positions'] as bool? ?? false;
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildGroupProfileCard(settingsService),
                  const SizedBox(height: 16),
                  _buildPreferencesCard(settingsService),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(LucideIcons.wallet),
                      title: const Text('Recebimentos e pagamentos'),
                      subtitle: const Text(
                        'Configure PIX e gateway exclusivos deste grupo.',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PaymentSettingsScreen(groupId: widget.groupId),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGroupProfileCard(SettingsService settingsService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dados do grupo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              readOnly: !_isEditingProfile,
              decoration: const InputDecoration(labelText: 'Nome do grupo'),
            ),
            TextField(
              controller: _cityController,
              readOnly: !_isEditingProfile,
              decoration: const InputDecoration(labelText: 'Cidade'),
            ),
            TextField(
              controller: _neighborhoodController,
              readOnly: !_isEditingProfile,
              decoration: const InputDecoration(labelText: 'Bairro'),
            ),
            const SizedBox(height: 12),
            _buildEditActions(
              isEditing: _isEditingProfile,
              isSaving: _isSavingProfile,
              onEdit: () => setState(() => _isEditingProfile = true),
              onCancel: () => setState(() => _isEditingProfile = false),
              onSave: () => _saveGroupProfile(settingsService),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(SettingsService settingsService) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(LucideIcons.goal),
            title: const Text('Incluir goleiros automaticamente'),
            subtitle: const Text(
              'Preferência de sorteio aplicada somente a este grupo.',
            ),
            value: _includeGoalkeepers,
            onChanged: _isEditingPreferences
                ? (value) => setState(() => _includeGoalkeepers = value)
                : null,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(LucideIcons.scale),
            title: const Text('Considerar posições no sorteio'),
            subtitle: const Text(
              'Equilibra as posições ao distribuir os times deste grupo.',
            ),
            value: _considerPositions,
            onChanged: _isEditingPreferences
                ? (value) => setState(() => _considerPositions = value)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildEditActions(
              isEditing: _isEditingPreferences,
              isSaving: _isSavingPreferences,
              onEdit: () => setState(() => _isEditingPreferences = true),
              onCancel: () => setState(() => _isEditingPreferences = false),
              onSave: () => _savePreferences(settingsService),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditActions({
    required bool isEditing,
    required bool isSaving,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required VoidCallback onSave,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isEditing) ...[
          TextButton(
            onPressed: isSaving ? null : onCancel,
            child: const Text('CANCELAR'),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton.icon(
          onPressed: isSaving
              ? null
              : isEditing
              ? onSave
              : onEdit,
          icon: Icon(isEditing ? LucideIcons.save : LucideIcons.edit),
          label: Text(
            isSaving
                ? 'SALVANDO...'
                : isEditing
                ? 'SALVAR'
                : 'EDITAR',
          ),
        ),
      ],
    );
  }
}
