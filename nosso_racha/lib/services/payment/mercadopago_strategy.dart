import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:http/http.dart' as http;
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../models/payment_config_model.dart';
import 'payment_strategy.dart'; 

class MercadoPagoStrategy implements PaymentStrategy {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Map<String, dynamic>> generatePix({
    required EventModel event,
    required UserModel payer,
    required PaymentConfigModel config,
  }) async {
    if (config.accessToken.isEmpty) {
      throw Exception("Token do Mercado Pago não configurado.");
    }

    final String payerEmail = payer.email.contains('@') ? payer.email : 'email_generico@lcs.com';
    final String payerName = payer.name.split(' ').first;
    final String payerLastName = payer.name.split(' ').length > 1 ? payer.name.split(' ').last : 'Atleta';

    // CORREÇÃO: Converter para UTC para garantir o formato ISO8601 com 'Z' no final
    // Ex: 2025-12-05T19:30:00.000Z
    final DateTime expirationDate = DateTime.now().add(const Duration(minutes: 10)).toUtc();
    final String expirationIso = expirationDate.toIso8601String();

    final body = {
      "transaction_amount": event.price,
      "description": "Racha LCS - ${event.title}",
      "payment_method_id": "pix",
      "date_of_expiration": expirationIso, // Data formatada corretamente
      "payer": {
        "email": payerEmail,
        "first_name": payerName,
        "last_name": payerLastName,
      },
      "metadata": {
        "event_id": event.id,
        "payer_uid": payer.uid,
        "env": config.accessToken.startsWith("TEST") ? "test" : "prod"
      }
    };

    print("Gerando PIX MP (Web: $kIsWeb). Expira em: $expirationIso");

    // Decisão de Roteamento (Web vs Mobile)
    if (kIsWeb) {
      return _generateViaCloudFunction(body, config.accessToken);
    } else {
      return _generateViaDirectHttp(body, config.accessToken, event.id!, payer.uid);
    }
  }

  // --- Métodos Internos Específicos do MP ---

  Future<Map<String, dynamic>> _generateViaCloudFunction(Map<String, dynamic> body, String token) async {
    try {
      final bool isTestKey = token.startsWith("TEST");

      final result = await _functions.httpsCallable('createMercadoPagoPix').call({
        'paymentData': body,
        'isTest': isTestKey, 
        'tempToken': isTestKey ? token : null, 
      });

      return _parseMpResponse(result.data);
    } catch (e) {
      if (e is FirebaseFunctionsException) {
        // Log detalhado para debug se possível
        print("Erro Cloud Function Detalhe: ${e.details}");
        throw Exception("Erro Cloud Function MP: ${e.message}");
      }
      throw Exception("Erro MP Web: $e");
    }
  }

  Future<Map<String, dynamic>> _generateViaDirectHttp(Map<String, dynamic> body, String token, String evtId, String userId) async {
    final url = Uri.parse('https://api.mercadopago.com/v1/payments');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-Idempotency-Key': '${evtId}_${userId}_${DateTime.now().millisecondsSinceEpoch}'
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        return _parseMpResponse(jsonDecode(response.body));
      } else {
        // Tenta extrair a mensagem de erro da resposta do MP
        String errorMsg = "Erro desconhecido";
        try {
           final errBody = jsonDecode(response.body);
           errorMsg = errBody['message'] ?? errBody.toString();
        } catch (_) {
           errorMsg = response.body;
        }
        throw Exception("Erro API MP (${response.statusCode}): $errorMsg");
      }
    } catch (e) {
      throw Exception("Falha conexão MP: $e");
    }
  }

  @override
  Future<void> refundPix(String paymentId, PaymentConfigModel config) async {
    try {
      await _functions.httpsCallable('refundMercadoPagoPix').call({
        'paymentId': paymentId,
      });
    } catch (e) {
       throw Exception("Erro ao estornar no MP: $e");
    }
  }

  Map<String, dynamic> _parseMpResponse(dynamic data) {
    if (data['point_of_interaction'] == null) {
       throw Exception("Resposta inválida do MP (sem point_of_interaction).");
    }
    return {
      'type': 'mercadopago',
      'qr_code': data['point_of_interaction']['transaction_data']['qr_code'],
      'qr_code_base64': data['point_of_interaction']['transaction_data']['qr_code_base64'],
      'payment_id': data['id'].toString(),
      'status': data['status'],
      'expiration_date': data['date_of_expiration'], 
    };
  }
}