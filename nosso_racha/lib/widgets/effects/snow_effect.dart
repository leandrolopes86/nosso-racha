import 'dart:math';
import 'package:flutter/material.dart';

class SnowOverlay extends StatefulWidget {
  final Widget child;
  final bool isEnabled;

  const SnowOverlay({
    super.key, 
    required this.child, 
    this.isEnabled = true
  });

  @override
  State<SnowOverlay> createState() => _SnowOverlayState();
}

class _SnowOverlayState extends State<SnowOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Snowflake> _snowflakes = [];
  final Random _random = Random();
  final int _flakeCount = 50; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1), 
    )..repeat();
    
    for (int i = 0; i < _flakeCount; i++) {
      _snowflakes.add(_generateSnowflake(randomY: true));
    }
  }

  _Snowflake _generateSnowflake({bool randomY = false}) {
    return _Snowflake(
      x: _random.nextDouble(), 
      y: randomY ? _random.nextDouble() : -0.1, 
      size: _random.nextDouble() * 3 + 2, 
      speed: _random.nextDouble() * 0.005 + 0.002, 
      opacity: _random.nextDouble() * 0.5 + 0.3, 
    );
  }

  void _updateSnowflakes() {
    for (var flake in _snowflakes) {
      flake.y += flake.speed;
      
      if (flake.y > 1.1) {
        var newFlake = _generateSnowflake(randomY: false);
        flake.x = newFlake.x;
        flake.y = newFlake.y;
        flake.speed = newFlake.speed;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // CORREÇÃO CRÍTICA:
    // Nunca retornamos 'widget.child' diretamente.
    // Retornamos sempre um 'Stack' para manter a estrutura da árvore de widgets estável.
    // Isso evita o erro "Multiple widgets used the same GlobalKey" no Navigator
    // quando o tema muda (de sem neve para com neve).
    
    return Stack(
      children: [
        // 1. O App (Navigator) fica sempre aqui, na base da Stack
        widget.child,
        
        // 2. A neve é desenhada por cima, SE estiver habilitada
        if (widget.isEnabled)
          Positioned.fill(
            child: IgnorePointer( // Deixa os cliques passarem para o App
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  _updateSnowflakes();
                  return CustomPaint(
                    painter: _SnowPainter(_snowflakes),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Snowflake {
  double x;
  double y;
  double size;
  double speed;
  double opacity;

  _Snowflake({required this.x, required this.y, required this.size, required this.speed, required this.opacity});
}

class _SnowPainter extends CustomPainter {
  final List<_Snowflake> snowflakes;

  _SnowPainter(this.snowflakes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var flake in snowflakes) {
      paint.color = Colors.white.withOpacity(flake.opacity);
      canvas.drawCircle(
        Offset(flake.x * size.width, flake.y * size.height),
        flake.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}