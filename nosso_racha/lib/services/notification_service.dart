import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'dart:io'; // Para Platform

class NotificationService {
  final FirebaseMessaging? _fcm;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _listenersAttached = false;

  NotificationService()
    : _fcm = _isFCMSupported() ? FirebaseMessaging.instance : null;

  static bool _isFCMSupported() {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<void> init() async {
    if (_fcm == null || _listenersAttached) return;

    try {
      // 1. Pedir Permissão
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('Permissão de notificação concedida.');

        // 2. Pegar Token (COM VAPID KEY PARA WEB)
        String? token;
        if (kIsWeb) {
          // ⚠️ ATENÇÃO: Cole sua chave VAPID abaixo, DENTRO das aspas.
          // Pegue em: Firebase Console > Configurações > Cloud Messaging > Web Push
          // Ela é uma string longa que geralmente começa com "B..."
          token = await _fcm.getToken(
            vapidKey:
                'BGFxntZ8ANzPH7EIlYFXFkAjEZAOpGVchkGN9gDn1bZV0WkA9yrqmBBPtzbz3r0GMPBzkLo7ZISa5FjaKgYsys4',
          );
        } else {
          token = await _fcm.getToken();
        }

        // 3. Salvar
        if (token != null && _auth.currentUser != null) {
          await _saveTokenToDatabase(token);
        }

        // 4. Inscrever no Tópico
        if (!kIsWeb) {
          try {
            await _fcm.subscribeToTopic('all_athletes');
          } catch (e) {
            debugPrint('Aviso ao inscrever no tópico: $e');
          }
        }

        // 5. Monitorar Refresh
        _fcm.onTokenRefresh.listen(_saveTokenToDatabase);

        // 6. Ouvir mensagens com o App ABERTO (Foreground)
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint(
            'Mensagem recebida em primeiro plano: '
            '${message.notification?.title}',
          );
          // Aqui você pode mostrar um SnackBar ou Dialog se quiser
        });
        _listenersAttached = true;
      } else {
        debugPrint('Permissão de notificação negada.');
      }
    } catch (e) {
      debugPrint('Erro ao inicializar FCM: $e');
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      await _firestore.collection('users').doc(uid).update({
        'fcm_token': token,
        'last_token_update': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao salvar token FCM: $e');
    }
  }
}
