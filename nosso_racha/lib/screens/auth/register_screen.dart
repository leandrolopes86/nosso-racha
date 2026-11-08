import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';

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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pixKeyController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  String? _selectedPosition;

  bool _isObscure = true;
  bool _isConfirmObscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pixKeyController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  // Validação rígida de e-mail
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      UserCredential userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passController.text.trim(),
          );

      final firebaseUser = userCred.user;
      if (firebaseUser != null) {
        await firebaseUser.sendEmailVerification();

        UserModel newUser = UserModel(
          uid: firebaseUser.uid,
          name: _nameController.text.trim(),
          nickname: _nicknameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          role: 'athlete',
          status: 'active',
          positions: [_selectedPosition!],
          pixKey: _pixKeyController.text.trim(),
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .set(newUser.toMap());

        if (!mounted) return;
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.reloadUser();

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Cadastro realizado! Enviamos um link de confirmação para o seu e-mail.",
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
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
            content: Text(
              "Erro ao cadastrar: ${e.toString().replaceAll('Exception: ', '')}",
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleRegister() async {
    if (_selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma posição.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      UserCredential userCred = await FirebaseAuth.instance.signInWithPopup(
        googleProvider,
      );
      final firebaseUser = userCred.user;

      if (firebaseUser != null) {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid);
        final docSnapshot = await docRef.get();

        if (!docSnapshot.exists) {
          UserModel newUser = UserModel(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName ?? 'Usuário',
            email: firebaseUser.email ?? '',
            phone: firebaseUser.phoneNumber ?? '',
            role: 'athlete',
            status: 'active',
            positions: [_selectedPosition!],
            pixKey: _pixKeyController.text.trim(),
          );
          await docRef.set(newUser.toMap());
        }

        if (!mounted) return;
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.reloadUser();

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Erro com Google: ${e.toString().replaceAll('Exception: ', '')}",
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
    const brandColor = Colors.green;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 5,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
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
                      "Criar Nova Conta",
                      style: TextStyle(
                        fontSize: 20,
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

                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleRegister,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                  icon: const Icon(
                    Icons.g_mobiledata,
                    size: 28,
                    color: Colors.red,
                  ),
                  label: const Text(
                    "Cadastrar com o Google",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        "OU",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Nome Completo
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Nome Completo *",
                    prefixIcon: Icon(LucideIcons.user),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Digite seu nome completo"
                      : null,
                ),
                const SizedBox(height: 14),

                // Apelido
                TextFormField(
                  controller: _nicknameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "Apelido (Opcional)",
                    prefixIcon: Icon(LucideIcons.userCheck),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // E-mail com Validação Ativa
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: "E-mail *",
                    prefixIcon: Icon(LucideIcons.mail),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return "Digite seu e-mail";
                    if (!_isValidEmail(value.trim()))
                      return "E-mail inválido (ex: nome@dominio.com)";
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Telefone com Máscara Automática e Validação
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [_PhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: "Telefone / WhatsApp *",
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
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  initialValue: _selectedPosition,
                  decoration: const InputDecoration(
                    labelText: 'Posição *',
                    prefixIcon: Icon(Icons.sports_soccer),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Goleiro', child: Text('Goleiro')),
                    DropdownMenuItem(
                      value: 'Zagueiro',
                      child: Text('Zagueiro'),
                    ),
                    DropdownMenuItem(
                      value: 'Meio-campo',
                      child: Text('Meio-campo'),
                    ),
                    DropdownMenuItem(
                      value: 'Atacante',
                      child: Text('Atacante'),
                    ),
                  ],
                  onChanged: (position) {
                    setState(() => _selectedPosition = position);
                  },
                  validator: (value) =>
                      value == null ? 'Selecione sua posição' : null,
                ),
                if (_selectedPosition == 'Goleiro') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pixKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Chave PIX para recebimento (opcional)',
                      prefixIcon: Icon(Icons.pix),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Senha
                TextFormField(
                  controller: _passController,
                  obscureText: _isObscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: "Senha (mínimo 6 dígitos) *",
                    prefixIcon: const Icon(LucideIcons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isObscure ? LucideIcons.eye : LucideIcons.eyeOff,
                      ),
                      onPressed: () => setState(() => _isObscure = !_isObscure),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return "Digite sua senha";
                    if (value.length < 6)
                      return "A senha deve ter pelo menos 6 caracteres";
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Confirmar Senha
                TextFormField(
                  controller: _confirmPassController,
                  obscureText: _isConfirmObscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleRegister(),
                  decoration: InputDecoration(
                    labelText: "Confirmar Senha *",
                    prefixIcon: const Icon(LucideIcons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmObscure
                            ? LucideIcons.eye
                            : LucideIcons.eyeOff,
                      ),
                      onPressed: () => setState(
                        () => _isConfirmObscure = !_isConfirmObscure,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return "Confirme sua senha";
                    if (value != _passController.text)
                      return "As senhas não coincidem";
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandColor,
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
                          "CADASTRAR",
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
