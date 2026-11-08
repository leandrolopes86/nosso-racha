import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EasterEggScreen extends StatefulWidget {
  const EasterEggScreen({super.key});

  @override
  State<EasterEggScreen> createState() => _EasterEggScreenState();
}

class _EasterEggScreenState extends State<EasterEggScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Configura uma animação de "pulsar" (Zoom In/Out)
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true); // Repete num loop de vai e volta

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD700), // Dourado (Ouro)
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ícone Animado
              ScaleTransition(
                scale: _scaleAnimation,
                child: Icon(LucideIcons.trophy, size: 120, color: Colors.black),
              ),
              const SizedBox(height: 40),

              const Text(
                "PARABÉNS!",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Você encontrou o segredo!",
                style: TextStyle(fontSize: 18, color: Colors.black87),
              ),
              const SizedBox(height: 40),

              // O Prêmio
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5))
                    ]),
                child: const Column(
                  children: [
                    Text(
                      "🎁 PRÊMIO DESBLOQUEADO",
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "1 RACHA GRÁTIS",
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32)),
                    ),
                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.camera, size: 20),
                        SizedBox(width: 8),
                        Text("Tire um print e envie no grupo!"),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
