import 'package:flutter/foundation.dart'; // Necessário para kIsWeb e TargetPlatform
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../widgets/pwa/ios_install_guide.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'profile_modal.dart'; // Importa o modal de edição de perfil que criamos antes

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();
  bool _isChangingPassword = false;
  bool _isReloading = false;

  bool get _isIOSWeb {
    return kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);
  }

  Future<void> _refreshProfile(AuthService authService) async {
    setState(() => _isReloading = true);
    await authService.reloadUser();
    if (mounted) {
      setState(() => _isReloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Perfil e permissões atualizados!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    if (user == null)
      return const Scaffold(
        body: Center(child: Text("Erro ao carregar perfil")),
      );

    String roleDisplay = "ATLETA";
    if (user.role == 'org') {
      roleDisplay = "STAFF / ORG";
    } else if (user.role == 'master') {
      roleDisplay = user.positions.isEmpty ? "STAFF / ORG" : "ATLETA";
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String lastMatchDisplay = "Nunca participou";
    if (user.lastMatchDate != null) {
      lastMatchDisplay = DateFormat('dd/MM/yyyy').format(user.lastMatchDate!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meu Perfil"),
        actions: [
          // BOTÃO DE EDITAR PERFIL
          IconButton(
            icon: Icon(LucideIcons.edit),
            tooltip: "Editar Perfil",
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (context) => const ProfileModal(),
              );
              setState(() {}); // Atualiza a tela ao fechar o modal
            },
          ),
          // BOTÃO DE ATUALIZAR PERMISSÕES
          if (_isReloading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(LucideIcons.refreshCw),
              tooltip: "Atualizar Dados e Permissões",
              onPressed: () => _refreshProfile(authService),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
        child: Column(
          children: [
            // --- CABEÇALHO DO PERFIL ---
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.2),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (user.nickname.isNotEmpty)
                      Text(
                        '"${user.nickname}"',
                        style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(roleDisplay),
                      backgroundColor: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.1),
                      labelStyle: TextStyle(
                        color: isDark
                            ? Colors.white
                            : Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                      side: BorderSide.none,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- BOTÃO DE INSTALAÇÃO IOS ---
            if (_isIOSWeb) ...[
              Card(
                color: isDark ? Colors.grey[800] : Colors.blue[50],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.withOpacity(0.3)),
                ),
                child: ListTile(
                  leading: Icon(LucideIcons.download, color: Colors.blue),
                  title: const Text(
                    "Instalar Aplicativo",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  subtitle: const Text(
                    "Adicione à tela de início do seu iPhone para melhor experiência.",
                  ),
                  trailing: Icon(LucideIcons.chevronRight, color: Colors.blue),
                  onTap: () => showIOSInstallGuide(context),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- ESTATÍSTICAS ---
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "ESTATÍSTICAS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      "Jogos",
                      "${user.matchesPlayed}",
                      LucideIcons.trophy,
                    ),
                    _buildStatItem(
                      "Faltas",
                      "${user.noShows}",
                      LucideIcons.alertCircle,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- DADOS PESSOAIS ---
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "DADOS PESSOAIS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),

            _buildInfoTile(context, LucideIcons.mail, "Email", user.email),
            _buildInfoTile(
              context,
              LucideIcons.phone,
              "Telefone / WhatsApp",
              user.phone,
            ),
            _buildInfoTile(
              context,
              LucideIcons.shirt,
              "Posições",
              user.positions.join(', '),
            ),
            _buildInfoTile(
              context,
              LucideIcons.calendarClock,
              "Último Jogo",
              lastMatchDisplay,
            ),

            const SizedBox(height: 32),

            if (!_isChangingPassword)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _isChangingPassword = true),
                  icon: Icon(LucideIcons.lock),
                  label: const Text("ALTERAR SENHA"),
                ),
              )
            else
              _buildChangePasswordForm(authService),

            // --- VERSÃO DO APP DINÂMICA ---
            const SizedBox(height: 32),
            Center(
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    final info = snapshot.data!;
                    final String version = info.version;
                    final String buildNumber = info.buildNumber;

                    return Text(
                      "Versão $version ($buildNumber) (Fase Beta)",
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                  return Text(
                    "Carregando versão...",
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        subtitle: Text(
          value.isEmpty ? '-' : value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildChangePasswordForm(AuthService authService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Alterar Senha",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currentPassController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Senha Atual",
                prefixIcon: Icon(LucideIcons.lock),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _newPassController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Nova Senha",
                prefixIcon: Icon(LucideIcons.key),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPassController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirmar Nova Senha",
                prefixIcon: Icon(LucideIcons.check),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _isChangingPassword = false),
                    child: const Text("CANCELAR"),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _submitChangePassword(authService),
                    child: authService.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text("SALVAR"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitChangePassword(AuthService authService) async {
    if (_newPassController.text != _confirmPassController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("A nova senha e a confirmação não conferem."),
        ),
      );
      return;
    }
    try {
      await authService.changePassword(
        _currentPassController.text,
        _newPassController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Senha alterada!"),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isChangingPassword = false;
          _currentPassController.clear();
          _newPassController.clear();
          _confirmPassController.clear();
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
    }
  }
}
