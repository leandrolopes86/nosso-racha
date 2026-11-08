import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';

// --- FORMATADOR DE MÁSCARA PARA TELEFONE (XX) XXXXX-XXXX ---
class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.length > 11) text = text.substring(0, 11);

    var buffer = StringBuffer();
    if (text.isNotEmpty) {
      buffer.write('(');
      if (text.length >= 2) {
        buffer.write('${text.substring(0, 2)}) ');
        if (text.length <= 6) {
          buffer.write(text.substring(2));
        } else if (text.length <= 10) {
          buffer.write('${text.substring(2, 6)}-${text.substring(6)}');
        } else {
          buffer.write('${text.substring(2, 7)}-${text.substring(7)}');
        }
      } else {
        buffer.write(text);
      }
    }

    String result = buffer.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

class ProfileModal extends StatefulWidget {
  const ProfileModal({super.key});

  @override
  State<ProfileModal> createState() => _ProfileModalState();
}

class _ProfileModalState extends State<ProfileModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _nicknameController;
  late TextEditingController _phoneController;
  late TextEditingController _pixKeyController;

  // Controladores para a alteração de senha
  final _currentPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _isLoading = false;
  bool _isChangingPassword = false;
  bool _isObscureCurrent = true;
  bool _isObscureNew = true;
  bool _isObscureConfirm = true;

  // Lista de posições disponíveis no app
  final List<String> _posicoesDisponiveis = [
    'Goleiro',
    'Zagueiro',
    'Meio-campo',
    'Atacante',
  ];
  final List<String> _posicoesSelecionadas = [];

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    _nameController = TextEditingController(text: user?.name ?? '');
    _nicknameController = TextEditingController(text: user?.nickname ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _pixKeyController = TextEditingController(text: user?.pixKey ?? '');

    if (user != null && user.positions.isNotEmpty) {
      _posicoesSelecionadas.addAll(user.positions);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _pixKeyController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;

      if (user != null) {
        if (_posicoesSelecionadas.isEmpty) {
          throw Exception('Selecione pelo menos uma posição.');
        }
        if (!user.canPlayMultiplePositions &&
            _posicoesSelecionadas.length > 1) {
          throw Exception('Atletas do plano Free podem escolher uma posição.');
        }

        final bool isPasswordUser =
            FirebaseAuth.instance.currentUser?.providerData.any(
              (userInfo) => userInfo.providerId == 'password',
            ) ??
            false;

        if (isPasswordUser &&
            _isChangingPassword &&
            _newPassController.text.isNotEmpty) {
          if (_newPassController.text != _confirmPassController.text) {
            throw Exception("A nova senha e a confirmação não conferem.");
          }
          if (_newPassController.text.length < 6) {
            throw Exception("A nova senha deve ter pelo menos 6 caracteres.");
          }
          await authService.changePassword(
            _currentPassController.text.trim(),
            _newPassController.text.trim(),
          );
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'personal_info.full_name': _nameController.text.trim(),
              'personal_info.phone_raw': _phoneController.text.trim(),
              'football_stats.nickname': _nicknameController.text.trim(),
              'football_stats.positions': _posicoesSelecionadas,
              'payment_info.pix_key': _pixKeyController.text.trim(),
            });

        await authService.reloadUser();

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Perfil atualizado com sucesso!"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final user = authService.currentUser;
    final bool isOrganizer =
        user != null && (user.isStaff || user.canCreateEvent);

    final bool isPasswordUser =
        FirebaseAuth.instance.currentUser?.providerData.any(
          (userInfo) => userInfo.providerId == 'password',
        ) ??
        false;

    final double modalHeight = kIsWeb
        ? 780
        : MediaQuery.of(context).size.height * 0.82;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 5,
      child: Container(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: modalHeight),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho fixo do modal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Editar Perfil",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Conteúdo com rolagem fluida
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Avatar e Cargo / Status PRO
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.green[100],
                              child: Text(
                                user?.name.isNotEmpty == true
                                    ? user!.name[0].toUpperCase()
                                    : 'U',
                                style: TextStyle(
                                  fontSize: 28,
                                  color: Colors.green[850],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isOrganizer
                                        ? Colors.purple[50]
                                        : Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isOrganizer
                                          ? Colors.purple[200]!
                                          : Colors.green[200]!,
                                    ),
                                  ),
                                  child: Text(
                                    isOrganizer
                                        ? 'CONTA PRO / ORGANIZADOR'
                                        : 'ATLETA',
                                    style: TextStyle(
                                      color: isOrganizer
                                          ? Colors.purple[800]
                                          : Colors.green[800],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (user != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: user.effectivePlan == 'organizer_vip'
                                ? Colors.purple[50]
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.hasActiveVipPlan
                                    ? 'VIP ${user.vipPlan}'
                                    : user.effectivePlan == 'organizer_vip'
                                    ? 'Plano Organizador VIP'
                                    : user.effectivePlan == 'athlete_vip'
                                    ? 'Plano Atleta VIP'
                                    : user.isStaff || user.canCreateEvent
                                    ? 'Plano Organizador'
                                    : 'Plano Free',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Organizações das quais participa: ${user.planLimits.maxGroupMemberships?.toString() ?? 'ilimitadas'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (user.canCreateOrganizations)
                                const Text(
                                  'Comunidades próprias: ilimitadas',
                                  style: TextStyle(fontSize: 12),
                                ),
                              if (user.isStaff || user.canCreateEvent) ...[
                                Text(
                                  'Rachas em aberto: ${user.planLimits.maxOpenEvents?.toString() ?? 'ilimitados'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Atletas por organização: ${user.planLimits.maxAthletesPerGroup?.toString() ?? 'ilimitados'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Co-organizadores: ${user.planLimits.maxCoOrganizersPerGroup?.toString() ?? 'ilimitados'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Nome Completo
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Nome Completo",
                          prefixIcon: Icon(LucideIcons.user),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? "Digite seu nome"
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Apelido
                      TextFormField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(
                          labelText: "Apelido",
                          prefixIcon: Icon(LucideIcons.userCheck),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // E-mail (BLOQUEADO)
                      TextFormField(
                        initialValue: user?.email ?? '',
                        enabled: false,
                        decoration: InputDecoration(
                          labelText: "E-mail (Não pode ser alterado)",
                          prefixIcon: const Icon(LucideIcons.mail),
                          border: const OutlineInputBorder(),
                          fillColor: Colors.grey[150],
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Telefone com Máscara Automática
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_PhoneInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: "Telefone / WhatsApp",
                          hintText: "(99) 99999-9999",
                          prefixIcon: Icon(LucideIcons.phone),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return "Digite seu telefone";
                          var rawDigits = value.replaceAll(RegExp(r'\D'), '');
                          if (rawDigits.length < 10)
                            return "Número de telefone incompleto";
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- SELEÇÃO DE POSIÇÕES ---
                      const Text(
                        "Posições em Campo",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _posicoesDisponiveis.map((posicao) {
                          final isSelected = _posicoesSelecionadas.contains(
                            posicao,
                          );
                          return FilterChip(
                            label: Text(posicao),
                            selected: isSelected,
                            selectedColor: Colors.green[100],
                            checkmarkColor: Colors.green[800],
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.green[900]
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  if (user?.canPlayMultiplePositions != true) {
                                    _posicoesSelecionadas.clear();
                                  }
                                  _posicoesSelecionadas.add(posicao);
                                } else {
                                  _posicoesSelecionadas.remove(posicao);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (_posicoesSelecionadas.contains('Goleiro')) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pixKeyController,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                            labelText: 'Chave PIX para recebimento (opcional)',
                            prefixIcon: Icon(Icons.pix),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // --- APARÊNCIA ---
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Aparência da página',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (themeService.isThemeLocked)
                                const ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(
                                    LucideIcons.lock,
                                    color: Colors.amber,
                                  ),
                                  title: Text(
                                    'O tema está definido pela organização.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                )
                              else
                                DropdownButtonFormField<String>(
                                  key: ValueKey(themeService.currentTheme),
                                  initialValue: themeService.currentTheme,
                                  decoration: const InputDecoration(
                                    labelText: 'Tema',
                                    prefixIcon: Icon(LucideIcons.palette),
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'light',
                                      child: Text('Claro'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'dark',
                                      child: Text('Escuro'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'purpleOrange',
                                      child: Text('Roxo e laranja'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pink',
                                      child: Text('Rosa'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'blue',
                                      child: Text('Azul'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'brazil',
                                      child: Text('Brasil'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'christmas',
                                      child: Text('Natal'),
                                    ),
                                  ],
                                  onChanged: (theme) {
                                    if (theme != null) {
                                      themeService.setTheme(theme);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // --- SEÇÃO CONDICIONAL DE SENHA ---
                      if (isPasswordUser) ...[
                        ExpansionTile(
                          initiallyExpanded: _isChangingPassword,
                          onExpansionChanged: (expanded) {
                            setState(() => _isChangingPassword = expanded);
                          },
                          title: const Text(
                            "Alterar Senha",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          leading: const Icon(
                            LucideIcons.lock,
                            color: Colors.green,
                          ),
                          children: [
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _currentPassController,
                              obscureText: _isObscureCurrent,
                              decoration: InputDecoration(
                                labelText: "Senha Atual",
                                prefixIcon: const Icon(LucideIcons.key),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isObscureCurrent
                                        ? LucideIcons.eye
                                        : LucideIcons.eyeOff,
                                  ),
                                  onPressed: () => setState(
                                    () =>
                                        _isObscureCurrent = !_isObscureCurrent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _newPassController,
                              obscureText: _isObscureNew,
                              decoration: InputDecoration(
                                labelText: "Nova Senha (mínimo 6 dígitos)",
                                prefixIcon: const Icon(LucideIcons.lock),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isObscureNew
                                        ? LucideIcons.eye
                                        : LucideIcons.eyeOff,
                                  ),
                                  onPressed: () => setState(
                                    () => _isObscureNew = !_isObscureNew,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _confirmPassController,
                              obscureText: _isObscureConfirm,
                              decoration: InputDecoration(
                                labelText: "Confirmar Nova Senha",
                                prefixIcon: const Icon(LucideIcons.checkCircle),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isObscureConfirm
                                        ? LucideIcons.eye
                                        : LucideIcons.eyeOff,
                                  ),
                                  onPressed: () => setState(
                                    () =>
                                        _isObscureConfirm = !_isObscureConfirm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Colors.grey,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Conta conectada via Google. A gestão de senha é feita diretamente na sua Conta Google.",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Botão de Salvar Fixo no Rodapé do Modal
              ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
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
                        "SALVAR ALTERAÇÕES",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
