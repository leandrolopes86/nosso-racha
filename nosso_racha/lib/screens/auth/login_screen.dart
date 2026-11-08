import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _emailFocusNode = FocusNode();

  bool _isObscure = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool('remember_me') ?? false;

      if (!mounted) return;

      if (remember) {
        setState(() {
          _rememberMe = true;
          _emailController.text = prefs.getString('saved_email') ?? '';
          _passController.text = prefs.getString('saved_pass') ?? '';
        });
      }

      if (_emailController.text.isEmpty) {
        _emailFocusNode.requestFocus();
      }
    } catch (_) {
      // Ignora erros de SharedPreferences se houver falha de ambiente web
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    TextInput.finishAutofillContext();

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_email', _emailController.text.trim());
        await prefs.setString('saved_pass', _passController.text.trim());
      } else {
        await prefs.remove('remember_me');
        await prefs.remove('saved_email');
        await prefs.remove('saved_pass');
      }

      // Adicionamos um timeout de 6 segundos para forçar o erro caso o Firebase trave
      await authService.signIn(
        _emailController.text.trim(),
        _passController.text.trim(),
      ).timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          throw Exception("O Firebase demorou muito para responder. Verifique sua conexão ou o Console do Firebase.");
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false); // Destrava o botão com certeza
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Aviso de Conexão"),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showForgotPasswordDialog() {
    final emailResetController = TextEditingController(text: _emailController.text);
    final messenger = ScaffoldMessenger.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Recuperar Senha"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Digite seu e-mail para receber o link de redefinição."),
              const SizedBox(height: 16),
              TextField(
                controller: emailResetController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(LucideIcons.mail),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("CANCELAR"),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailResetController.text.trim();
                if (email.isEmpty) return;

                Navigator.pop(dialogContext);

                try {
                  await authService.resetPassword(email);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text("Email de recuperação enviado!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text("Erro: ${e.toString().replaceAll('Exception: ', '')}"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text("ENVIAR"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Colors.green;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 5,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: AutofillGroup(
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
                        "Acessar Conta",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(LucideIcons.mail),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? "Digite seu email" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passController,
                    obscureText: _isObscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _handleLogin(),
                    decoration: InputDecoration(
                      labelText: "Senha",
                      prefixIcon: const Icon(LucideIcons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_isObscure ? LucideIcons.eye : LucideIcons.eyeOff),
                        onPressed: () => setState(() => _isObscure = !_isObscure),
                      ),
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? "Digite sua senha" : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            activeColor: brandColor,
                            onChanged: (value) {
                              setState(() {
                                _rememberMe = value ?? false;
                              });
                            },
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: const Text("Lembrar de mim", style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text("Esqueceu?", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Botão principal de Entrar com E-mail e Senha
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text("ENTRAR", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),

                  const SizedBox(height: 16),
                  
                  // Divisor "OU"
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text("OU", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Botão de Login com Google
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : () async {
                      setState(() => _isLoading = true);
                      final authService = Provider.of<AuthService>(context, listen: false);
                      try {
                        await authService.signInWithGoogle();
                        if (mounted) {
                          Navigator.pop(context, true); // Fecha o modal e atualiza a home
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Erro ao logar com Google: ${e.toString().replaceAll('Exception: ', '')}"),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    icon: const Icon(Icons.g_mobiledata, size: 28, color: Colors.red), // Ou use uma imagem do ícone do Google se preferir
                    label: const Text(
                      "Continuar com o Google",
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
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