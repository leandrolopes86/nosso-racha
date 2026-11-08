import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'web_reload_stub.dart'
    if (dart.library.js_interop) 'web_reload_web.dart'
    as platform;

class WebUpdateService {
  // Retorna TRUE se houver uma nova versão disponível
  static Future<bool> checkForUpdate() async {
    if (!kIsWeb) return false; // Só roda na web

    try {
      // 1. Pega a versão atual (que o Flutter carregou na memória)
      // Nota: O Flutter gera um version.json no build web assets
      final currentVersionContent = await http.get(Uri.parse('version.json'));

      // 2. Pega a versão do servidor (adiciona timestamp para evitar cache do browser)
      final serverVersionContent = await http.get(
        Uri.parse('version.json?v=${DateTime.now().millisecondsSinceEpoch}'),
      );

      if (currentVersionContent.statusCode == 200 &&
          serverVersionContent.statusCode == 200) {
        final Map<String, dynamic> currentData = jsonDecode(
          currentVersionContent.body,
        );
        final Map<String, dynamic> serverData = jsonDecode(
          serverVersionContent.body,
        );

        final String currentBuild = currentData['build_number'] ?? '0';
        final String serverBuild = serverData['build_number'] ?? '0';

        debugPrint(
          'Versão atual (cache): $currentBuild | '
          'Versão do servidor: $serverBuild',
        );

        // Se o número da build no servidor for maior ou diferente, precisa atualizar
        if (serverBuild != currentBuild) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar atualização web: $e');
    }
    return false;
  }

  static void reloadPage() => platform.reloadPage();
}
