import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class IOSInstallGuide extends StatelessWidget {
  const IOSInstallGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/logo.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (_, __, ___) => Icon(LucideIcons.appWindow)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Instalar LCS App",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("Para iPhone e iPad",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const Divider(height: 32),

          _buildStep(
            context,
            number: 1,
            text:
                'Toque no botão "Compartilhar" na barra inferior do navegador.',
            icon: Icons.ios_share, // Ícone nativo do iOS Share
            isIcon: true,
          ),
          const SizedBox(height: 16),
          _buildStep(
            context,
            number: 2,
            text: 'Role para baixo e selecione "Adicionar à Tela de Início".',
            icon: LucideIcons.plusSquare,
            isIcon: true,
          ),
          const SizedBox(height: 16),
          _buildStep(
            context,
            number: 3,
            text: 'Toque em "Adicionar" no canto superior direito.',
            textAction: "Adicionar", // Texto simulando o botão do iOS
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        "Isso fará o app funcionar em tela cheia e offline.",
                        style: TextStyle(fontSize: 12, color: Colors.orange))),
              ],
            ),
          ),
          const SizedBox(height: 24), // Espaço para a barra de home do iPhone
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context,
      {required int number,
      required String text,
      IconData? icon,
      String? textAction,
      bool isIcon = false}) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
          child: Text("$number",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        const SizedBox(width: 12),
        if (isIcon && icon != null)
          Icon(icon, color: Colors.blue, size: 28), // Azul padrão do iOS
        if (!isIcon && textAction != null)
          Text(textAction,
              style: const TextStyle(
                  color: Colors.blue, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Método estático para facilitar a chamada
void showIOSInstallGuide(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // Permite que o modal cresça se necessário
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => const IOSInstallGuide(),
  );
}
