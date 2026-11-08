import 'package:flutter/foundation.dart'; // Necessário para kIsWeb
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Aguarda 3 segundos fixos para exibir a marca
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Aguarda o AuthService terminar de verificar o Firebase
    while (authService.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => authService.currentUser != null 
            ? const HomeScreen() 
            : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // --- CORREÇÃO: Usa as cores do Tema Ativo ---
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    // Usa a cor primária para o loading (garante contraste em todos os temas: Branco no Natal, Verde no Padrão)
    final loadingColor = Theme.of(context).colorScheme.primary; 

    // --- LAYOUT WEB (Mantido igual pois estava perfeito) ---
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
                  width: size.width * 0.8,
                  height: size.height * 0.6, 
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.sports_soccer, size: 100, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 32),
                CircularProgressIndicator(color: loadingColor),
              ],
            ),
          ),
        ),
      );
    } 
    
    // --- LAYOUT MOBILE (Corrigido para não esticar) ---
    else {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Espaçador para empurrar a logo um pouco para cima visualmente
              const Spacer(),
              
              // Logo centralizada e controlada
              SizedBox(
                width: size.width * 0.6, // Ocupa 60% da largura da tela no máximo
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain, // Garante que a imagem apareça inteira
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.sports_soccer, size: 80, color: Colors.green),
                ),
              ),
              
              const Spacer(), // Mantém o loading separado no rodapé ou logo abaixo
              
              Padding(
                padding: const EdgeInsets.only(bottom: 60.0),
                child: CircularProgressIndicator(
                  color: loadingColor, // Adaptativo ao tema
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}