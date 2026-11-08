import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necessário para o FilteringTextInputFormatter
import 'package:provider/provider.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';

class RegisterGuestScreen extends StatefulWidget {
  final UserModel? userToEdit;
  final String? groupId;

  const RegisterGuestScreen({super.key, this.userToEdit, this.groupId});

  @override
  State<RegisterGuestScreen> createState() => _RegisterGuestScreenState();
}

class _RegisterGuestScreenState extends State<RegisterGuestScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _pixKeyController = TextEditingController();

  String _status = 'active';
  bool _isPlayer = true;
  bool _isMaster = false;

  // Alterado: Escala base 1-99 (OVR)
  double _rating = 1.0;

  final Map<String, bool> _positions = {
    'Goleiro': false,
    'Zagueiro': false,
    'Meio Campo': false,
    'Atacante': false,
  };

  // Permissões
  final Map<String, bool> _staffPermissions = {
    'can_create_event': false,
    'can_sort_teams': false,
    'can_generate_tiers': false,
    'can_reopen_tiers': false,
    'can_reopen_teams': false,
    'can_end_event': false,
    'can_edit_event': false,
    'can_add_player': false,
    'can_share_list': false,
    'can_remove_unpaid': false,
    'can_remove_player': false,
    'can_mark_paid': false,
    'can_reorder_list': false,
    'can_sync_payments': false,
    'can_view_financial_summary': false,
    'can_view_finance': false,
    'can_manage_finance': false,
    'can_revert_match': false,
    'can_edit_match_score': false,
    'can_update_live_score': false,
    'can_register_user': false,
    'can_change_account_status': false,
    'can_edit_personal_data': false,
    'can_define_positions': false,
    'can_edit_technical_rating': false,
    'can_view_reports': false,
    'can_add_guest_player': false,
  };

  final Map<String, String> _permissionLabels = {
    'can_create_event': 'Criar Novo Jogo',
    'can_sort_teams': 'Sortear Times (Ação Final)',
    'can_generate_tiers': 'Gerar/Sortear Níveis',
    'can_reopen_tiers': 'Reabrir Níveis (Destravar)',
    'can_reopen_teams': 'Reabrir Sorteio (Destravar)',
    'can_end_event': 'Encerrar Racha',
    'can_edit_event': 'Editar Dados do Racha',
    'can_add_player': 'Adicionar Atleta Manualmente',
    'can_share_list': 'Compartilhar Lista',
    'can_remove_unpaid': 'Remover Não Pagos',
    'can_remove_player': 'Remover Atleta da Lista',
    'can_mark_paid': 'Validar Pagamento',
    'can_reorder_list': 'Arrastar/Reordenar Lista',
    'can_sync_payments': 'Sincronizar Pagamentos (Gateway)',
    'can_view_financial_summary': 'Visualizar Resumo Financeiro (Evento)',
    'can_view_finance': 'Visualizar Saldo/Caixa Geral',
    'can_manage_finance': 'Lançar Receitas/Despesas no Caixa',
    'can_revert_match': 'Reverter Jogo (Desfazer)',
    'can_edit_match_score': 'Editar Placar / Gols',
    'can_update_live_score': 'Atualizar Placar ao Vivo',
    'can_register_user': 'Criar Novo Atleta',
    'can_change_account_status': 'Alterar Status da Conta',
    'can_edit_personal_data': 'Alterar Dados Pessoais',
    'can_define_positions': 'Definir Posições de Jogo',
    'can_edit_technical_rating': 'Alterar Nota Técnica',
    'can_view_reports': 'Visualizar Relatórios e Estatísticas',
    'can_add_guest_player': 'Adicionar Atleta Avulso (Fechamento)',
  };

  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );
  final _dateMask = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      _loadUserData(widget.userToEdit!);
    }
  }

  void _loadUserData(UserModel u) {
    _nameController.text = u.name;
    _nicknameController.text = u.nickname;
    _emailController.text = u.email;
    _pixKeyController.text = u.pixKey;

    if (u.phone.isNotEmpty)
      _phoneController.text = _phoneMask.maskText(u.phone);
    _birthDateController.text = u.birthDate;

    _status = u.status;
    _isMaster = u.isMaster;

    if (u.role == 'org') {
      _isPlayer = false;
    } else if (u.role == 'master') {
      if (u.isOwner) {
        _isPlayer = u.positions.isNotEmpty;
      } else {
        _isPlayer = false;
      }
    } else {
      _isPlayer = true;
    }

    // --- MIGRAR NOTA ANTIGA SE NECESSÁRIO (De 1-10 para 1-99) ---
    _rating = (u.rating > 0)
        ? u.rating
        : 1.0; // Se não houver nota, define como 1.0

    for (var pos in u.positions) {
      if (_positions.containsKey(pos)) {
        _positions[pos] = true;
      }
    }

    if (u.permissions.isNotEmpty) {
      u.permissions.forEach((key, value) {
        if (_staffPermissions.containsKey(key)) {
          _staffPermissions[key] = value == true;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _pixKeyController.dispose();
    super.dispose();
  }

  bool get _isTargetOwner => widget.userToEdit?.isOwner ?? false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (widget.userToEdit == null && !(currentUser?.canRegisterUser ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sem permissão para criar."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_isTargetOwner && _isPlayer) {
      _isMaster = false;
    }

    String finalRole;
    if (_isTargetOwner) {
      finalRole = _isPlayer ? 'athlete' : 'org';
    } else if (_isMaster) {
      finalRole = 'master';
    } else if (!_isPlayer) {
      finalRole = 'org';
    } else {
      finalRole = 'athlete';
    }

    List<String> finalPositions = _positions.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (finalPositions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Selecione pelo menos uma posição (necessário para sorteio).",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final canPlayMultiplePositions =
        finalRole == 'org' ||
        finalRole == 'master' ||
        (widget.userToEdit?.canPlayMultiplePositions ?? false);
    if (!canPlayMultiplePositions && finalPositions.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Atletas do plano Free podem escolher uma posição."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Map<String, bool> permissionsToSave = Map.from(_staffPermissions);
    if (finalRole == 'athlete' && !_isMaster && !_isTargetOwner) {
      permissionsToSave.updateAll((key, value) => false);
    }

    double finalRating = _rating;
    final userService = Provider.of<UserService>(context, listen: false);

    try {
      if (widget.userToEdit != null) {
        await userService.updateUser(
          widget.userToEdit!,
          name: _nameController.text.trim(),
          nickname: _nicknameController.text.trim(),
          phone: _phoneMask.getUnmaskedText(),
          pixKey: _pixKeyController.text.trim(),
          positions: finalPositions,
          rating: finalRating,
          status: _status,
          role: finalRole,
          email: _emailController.text.trim(),
          birthDate: _birthDateController.text.trim(),
          permissions: permissionsToSave,
          groupId: widget.groupId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Atualizado!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        await userService.registerUser(
          name: _nameController.text.trim(),
          nickname: _nicknameController.text.trim(),
          phone: _phoneMask.getUnmaskedText(),
          pixKey: _pixKeyController.text.trim(),
          positions: finalPositions,
          rating: finalRating,
          status: _status,
          role: finalRole,
          email: _emailController.text.trim(),
          birthDate: _birthDateController.text.trim(),
          permissions: permissionsToSave,
          groupId: widget.groupId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cadastrado!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red),
        );
    }
  }

  void _showPermissionsDialog() {
    final List<String> eventPermissions = [
      'can_create_event',
      'can_edit_event',
      'can_end_event',
      'can_share_list',
      'can_reorder_list',
      'can_add_player',
      'can_remove_player',
      'can_add_guest_player',
    ];

    final List<String> sortingPermissions = [
      'can_generate_tiers',
      'can_reopen_tiers',
      'can_sort_teams',
      'can_reopen_teams',
    ];

    final List<String> financePermissions = [
      'can_view_finance',
      'can_manage_finance',
      'can_mark_paid',
      'can_remove_unpaid',
      'can_sync_payments',
      'can_view_financial_summary',
    ];

    final List<String> matchPermissions = [
      'can_update_live_score',
      'can_edit_match_score',
      'can_revert_match',
    ];

    final List<String> userPermissions = [
      'can_register_user',
      'can_change_account_status',
      'can_edit_personal_data',
      'can_define_positions',
      'can_edit_technical_rating',
    ];
    final List<String> reportPermissions = ['can_view_reports'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Direitos de Acesso"),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPermissionSection(
                        "Gestão de Rachas",
                        eventPermissions,
                        setStateDialog,
                      ),
                      _buildPermissionSection(
                        "Gestão de Sorteios",
                        sortingPermissions,
                        setStateDialog,
                      ),
                      _buildPermissionSection(
                        "Gestão de Partidas",
                        matchPermissions,
                        setStateDialog,
                      ),
                      _buildPermissionSection(
                        "Financeiro",
                        financePermissions,
                        setStateDialog,
                      ),
                      _buildPermissionSection(
                        "Gestão de Atletas",
                        userPermissions,
                        setStateDialog,
                      ),
                      _buildPermissionSection(
                        "Relatórios",
                        reportPermissions,
                        setStateDialog,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPermissionSection(
    String title,
    List<String> keys,
    StateSetter setStateDialog,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).hintColor,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const Divider(height: 1),
        ...keys.map((key) {
          if (!_staffPermissions.containsKey(key))
            return const SizedBox.shrink();
          return CheckboxListTile(
            title: Text(
              _permissionLabels[key] ?? key,
              style: const TextStyle(fontSize: 14),
            ),
            value: _staffPermissions[key],
            activeColor: const Color(0xFF2E7D32),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onChanged: (val) {
              setStateDialog(() {
                _staffPermissions[key] = val!;
              });
            },
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  // --- LÓGICA DO BADGE FIFA ---
  Color _getBadgeColor(double rating) {
    if (rating >= 80) return Colors.amber[600]!; // Ouro
    if (rating >= 65) return Colors.blueGrey[400]!; // Prata
    return Colors.brown[400]!; // Bronze
  }

  void _showManualRatingInput() {
    final ctrl = TextEditingController(text: _rating.toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Definir Nível Geral (OVR)"),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: "1 a 99",
            suffixIcon: Icon(LucideIcons.star),
            helperText: "Informe um valor inteiro entre 1 e 99.",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null && val >= 1 && val <= 99) {
                setState(() {
                  _rating = val.toDouble();
                });
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("O valor deve estar entre 1 e 99"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("SALVAR"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    final isLoggedUserMaster = currentUser != null && currentUser.isMaster;
    final isSelfEditing =
        widget.userToEdit != null &&
        currentUser != null &&
        widget.userToEdit!.uid == currentUser.uid;

    // CORREÇÃO: Suspender usuário não exige mais email nem data
    bool requiresLogin = _status == 'active';
    bool showLoginFields =
        requiresLogin || (widget.userToEdit?.email.isNotEmpty ?? false);

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    bool isCreating = widget.userToEdit == null;
    bool canEditPersonal = isCreating
        ? (currentUser?.canRegisterUser ?? false)
        : (currentUser?.canEditPersonalData ?? false);
    bool canEditStatus = isCreating
        ? (currentUser?.canRegisterUser ?? false)
        : (currentUser?.canChangeAccountStatus ?? false);
    bool canEditPositions = isCreating
        ? (currentUser?.canRegisterUser ?? false)
        : (currentUser?.canDefinePositions ?? false);
    bool canEditRating = isCreating
        ? (currentUser?.canRegisterUser ?? false)
        : (currentUser?.canEditTechnicalRating ?? false);

    if (isLoggedUserMaster) {
      canEditPersonal = true;
      canEditStatus = true;
      canEditPositions = true;
      canEditRating = true;
    }
    bool canEditEmail = canEditPersonal;
    if (_isTargetOwner && !isSelfEditing) {
      canEditEmail = false;
    }

    bool canBeMaster = !_isPlayer || _isTargetOwner;

    return Scaffold(
      appBar: AppBar(
        title: Text(isCreating ? "Novo Cadastro" : "Editar Cadastro"),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                color: Theme.of(
                  context,
                ).cardTheme.color, // Usa cor do card do tema
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "DEFINIÇÕES DO PERFIL",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSelectableCard(
                              context: context,
                              icon: LucideIcons.user,
                              label: "ATLETA",
                              isSelected: _isPlayer,
                              onTap: isLoggedUserMaster
                                  ? () => setState(() {
                                      _isPlayer = true;
                                      if (!_isTargetOwner) _isMaster = false;
                                    })
                                  : () {},
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSelectableCard(
                              context: context,
                              icon: LucideIcons.clipboardList,
                              label: "ORG / STAFF",
                              isSelected: !_isPlayer,
                              onTap: isLoggedUserMaster
                                  ? () => setState(() {
                                      _isPlayer = false;
                                    })
                                  : () {},
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: "Status da Conta",
                          prefixIcon: Icon(LucideIcons.activity),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text("🟢 Ativo (Com Login)"),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text("⚪ Inativo / Convidado"),
                          ),
                          DropdownMenuItem(
                            value: 'suspended',
                            child: Text("🔴 Suspenso"),
                          ),
                        ],
                        onChanged: (_isTargetOwner || isSelfEditing)
                            ? null
                            : (canEditStatus
                                  ? (v) => setState(() => _status = v!)
                                  : null),
                      ),
                      if (isLoggedUserMaster && !isSelfEditing) ...[
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text(
                            "Acesso Master (Admin)",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            _isTargetOwner
                                ? "Super Admin (Imutável)"
                                : (canBeMaster
                                      ? "Tem acesso total a todas as funções."
                                      : "Apenas membros da Org/Staff podem ser Masters."),
                          ),
                          value: _isMaster,
                          activeThumbColor: const Color(0xFF2E7D32),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (_isTargetOwner || !canBeMaster)
                              ? null
                              : (val) => setState(() {
                                  _isMaster = val;
                                }),
                        ),
                      ],
                      if (!_isMaster && !_isPlayer && !isSelfEditing)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: OutlinedButton.icon(
                            onPressed: _showPermissionsDialog,
                            icon: Icon(LucideIcons.lock),
                            label: const Text("DEFINIR DIREITOS DE ACESSO"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                      if (_isMaster)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "ℹ️ Masters possuem todos os direitos automaticamente.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                "DADOS PESSOAIS",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Nome Completo",
                  prefixIcon: Icon(LucideIcons.user),
                ),
                enabled: canEditPersonal,
                validator: (v) => v!.isEmpty ? "Obrigatório" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: "Apelido",
                  prefixIcon: Icon(LucideIcons.userCheck),
                ),
                enabled: canEditPersonal,
                validator: (v) => v!.isEmpty ? "Obrigatório" : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      inputFormatters: [_phoneMask],
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Celular",
                        prefixIcon: Icon(LucideIcons.phone),
                      ),
                      enabled: canEditPersonal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _birthDateController,
                      inputFormatters: [_dateMask],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Nascimento",
                        prefixIcon: Icon(LucideIcons.calendar),
                      ),
                      enabled: canEditPersonal,
                      // CORREÇÃO: Usando a nova regra de validação
                      validator: (v) =>
                          (requiresLogin && (v == null || v.length < 10))
                          ? "Obrigatório"
                          : null,
                    ),
                  ),
                ],
              ),

              if (showLoginFields) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "E-mail (Login)",
                    prefixIcon: Icon(LucideIcons.mail),
                  ),
                  enabled: canEditEmail,
                  validator: (v) {
                    // CORREÇÃO: Só força o email se requiresLogin for true. Se não for, passa em branco.
                    if (!requiresLogin && (v == null || v.isEmpty)) return null;
                    if (v == null || v.isEmpty || !v.contains('@'))
                      return "Email válido necessário";
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    "Senha inicial será a data de nascimento (apenas números).",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),
              Text(
                "PERFIL TÉCNICO",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                "Posições:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                children: _positions.keys.map((pos) {
                  return FilterChip(
                    label: Text(pos),
                    selected: _positions[pos]!,
                    onSelected: canEditPositions
                        ? (bool selected) => setState(() {
                            final canPlayMultiplePositions =
                                !_isPlayer ||
                                _isMaster ||
                                (widget.userToEdit?.canPlayMultiplePositions ??
                                    false);
                            if (selected && !canPlayMultiplePositions) {
                              _positions.updateAll((key, _) => false);
                            }
                            _positions[pos] = selected;
                          })
                        : null,
                    selectedColor: Colors.green.withOpacity(0.2),
                    checkmarkColor: Colors.green,
                  );
                }).toList(),
              ),
              if (_positions['Goleiro'] == true) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pixKeyController,
                  decoration: const InputDecoration(
                    labelText: "Chave PIX do goleiro (opcional)",
                    prefixIcon: Icon(Icons.pix),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // --- LAYOUT DA NOTA TÉCNICA (OVR - ESTILO FIFA) ---
              const Text(
                "Nível Geral (OVR):",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ESCUDO (BADGE)
                  GestureDetector(
                    onTap: canEditRating ? _showManualRatingInput : null,
                    child: Container(
                      width: 65,
                      height: 75,
                      decoration: BoxDecoration(
                        color: _getBadgeColor(_rating),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                          bottom: Radius.circular(30),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _rating.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const Text(
                            "OVR",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // SLIDER E DICA
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: _getBadgeColor(_rating),
                            thumbColor: _getBadgeColor(_rating),
                            inactiveTrackColor: Colors.grey.withOpacity(0.3),
                          ),
                          child: Slider(
                            value: _rating,
                            min: 1,
                            max: 99,
                            divisions: 98,
                            onChanged: canEditRating
                                ? (v) => setState(() => _rating = v)
                                : null,
                          ),
                        ),
                        if (canEditRating)
                          const Padding(
                            padding: EdgeInsets.only(left: 16.0),
                            child: Text(
                              "Arraste ou toque no escudo para digitar",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              SizedBox(
                height: 50,
                child: Consumer<UserService>(
                  builder: (context, service, _) {
                    return ElevatedButton(
                      onPressed: service.isLoading ? null : _submit,
                      child: service.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              widget.userToEdit != null
                                  ? "SALVAR ALTERAÇÕES"
                                  : "FINALIZAR CADASTRO",
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectableCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedColor =
        Theme.of(context).cardTheme.color ??
        (isDark ? Colors.grey[800] : Colors.grey[100]);
    final borderColor = isSelected
        ? const Color(0xFF2E7D32)
        : (isDark ? Colors.grey[700]! : Colors.grey.shade300);
    final contentColor = isSelected
        ? Colors.white
        : Theme.of(context).iconTheme.color ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : unselectedColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: contentColor, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
