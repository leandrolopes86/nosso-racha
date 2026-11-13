import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/personal_data_validators.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cpfController;
  late final TextEditingController _phoneController;
  late final TextEditingController _birthDateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _cpfController = TextEditingController(text: formatCpf(user?.cpf));
    _phoneController = TextEditingController(
      text: formatBrazilianPhone(user?.phone),
    );
    _birthDateController = TextEditingController(
      text: birthDateForDisplay(user?.birthDate),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cpfController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  DateTime get _latestAllowedBirthDate {
    final now = DateTime.now();
    return DateTime(now.year - 18, now.month, now.day);
  }

  Future<void> _selectBirthDate() async {
    final latestDate = _latestAllowedBirthDate;
    final currentBirthDate = parseBirthDate(_birthDateController.text);
    final initialDate =
        currentBirthDate != null && !currentBirthDate.isAfter(latestDate)
        ? currentBirthDate
        : DateTime(latestDate.year - 10, latestDate.month, latestDate.day);
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: latestDate,
      helpText: 'Selecione sua data de nascimento',
    );
    if (selectedDate != null) {
      _birthDateController.text = DateFormat('dd/MM/yyyy').format(selectedDate);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await context.read<AuthService>().saveRequiredPersonalData(
        name: _nameController.text.trim(),
        cpf: _cpfController.text.trim(),
        phone: _phoneController.text.trim(),
        birthDate: birthDateForStorage(_birthDateController.text),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar seu perfil: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete seu cadastro'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Sair da conta',
            onPressed: _isSaving
                ? null
                : () => context.read<AuthService>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.person_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Precisamos completar seus dados antes de continuar.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe seu nome completo'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _cpfController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CpfInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'CPF *',
                      hintText: '000.000.000-00',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        isValidCpf(value) ? null : 'Informe um CPF válido',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      PhoneInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Telefone / WhatsApp *',
                      hintText: '(00) 00000-0000',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => isValidBrazilianPhone(value)
                        ? null
                        : 'Informe um telefone com DDD válido',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _birthDateController,
                    readOnly: true,
                    onTap: _selectBirthDate,
                    decoration: const InputDecoration(
                      labelText: 'Data de nascimento *',
                      hintText: 'DD/MM/AAAA',
                      suffixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => isAdult(parseBirthDate(value))
                        ? null
                        : 'É necessário ter pelo menos 18 anos',
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Salvar e continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
