import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/payment_config_model.dart';
import '../models/event_model.dart';
import '../models/user_model.dart';

// Importa as estratégias
import 'payment/payment_strategy.dart';
import 'payment/manual_strategy.dart';
import 'payment/mercadopago_strategy.dart';
import 'payment/payment_polling_policy.dart';

class PaymentGatewayService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final Map<String, Future<String>> _paymentStatusChecksInFlight = {};
  final Map<String, DateTime> _lastPaymentStatusCheckAt = {};
  final Map<String, String> _lastPaymentStatuses = {};

  PaymentConfigModel? _config;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  PaymentConfigModel? get config => _config;

  DocumentReference<Map<String, dynamic>> _configReference(String? groupId) {
    if (groupId == null) {
      return _firestore.collection('settings').doc('payment_gateway');
    }
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settings')
        .doc('payment_gateway');
  }

  // --- CARREGAMENTO DE CONFIGURAÇÃO ---
  Future<void> loadConfig({String? groupId}) async {
    try {
      final doc = await _configReference(groupId).get();
      if (doc.exists) {
        _config = PaymentConfigModel.fromMap(doc.data()!);
      } else {
        _config = PaymentConfigModel(provider: 'manual', isActive: true);
      }
      notifyListeners();
    } catch (e) {
      _config = null;
      rethrow;
    }
  }

  Future<void> saveConfig(
    PaymentConfigModel newConfig, {
    String? groupId,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _configReference(groupId).set(newConfig.toMap());
      _config = newConfig;
    } catch (e) {
      throw Exception('Erro ao salvar configuração: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- FÁBRICA DE ESTRATÉGIAS ---
  PaymentStrategy _getStrategy(String provider) {
    switch (provider) {
      case 'mercadopago':
        return MercadoPagoStrategy();
      case 'manual':
      default:
        return ManualPaymentStrategy();
    }
  }

  // --- MÉTODOS PÚBLICOS ---

  // Gera o PIX usando a estratégia selecionada
  Future<Map<String, dynamic>> generatePix({
    required EventModel event,
    required UserModel payer,
    PaymentConfigModel? configOverride,
  }) async {
    // CORREÇÃO: Se não tiver override e config estiver nula, carrega agora.
    if (configOverride == null) {
      await loadConfig(groupId: event.groupId);
    }

    final activeConfig = configOverride ?? _config;

    if (activeConfig == null) {
      throw Exception("Pagamento não configurado ou indisponível.");
    }

    // 1. Escolhe a estratégia baseada no provider
    final strategy = _getStrategy(activeConfig.provider);

    // 2. Delega a execução
    return await strategy.generatePix(
      event: event,
      payer: payer,
      config: activeConfig,
    );
  }

  // Estorna o PIX usando a estratégia do provedor atual
  Future<void> refundPix(String paymentId, {String? groupId}) async {
    // CORREÇÃO: Garante o carregamento antes de tentar estornar
    await loadConfig(groupId: groupId);

    if (_config == null)
      throw Exception(
        "Não foi possível carregar as configurações de pagamento.",
      );

    final strategy = _getStrategy(_config!.provider);

    await strategy.refundPix(paymentId, _config!);
  }

  // Verifica o status do pagamento (Polling)
  Future<String> checkPaymentStatus(String paymentId) async {
    if (paymentId.isEmpty || paymentId.startsWith('manual_')) return 'manual';

    final inFlightCheck = _paymentStatusChecksInFlight[paymentId];
    if (inFlightCheck != null) return inFlightCheck;

    final now = DateTime.now();
    final stalePaymentIds = _lastPaymentStatusCheckAt.entries
        .where(
          (entry) => now.difference(entry.value) > const Duration(minutes: 2),
        )
        .map((entry) => entry.key)
        .toList();
    for (final stalePaymentId in stalePaymentIds) {
      _lastPaymentStatusCheckAt.remove(stalePaymentId);
      _lastPaymentStatuses.remove(stalePaymentId);
    }
    final lastCheckedAt = _lastPaymentStatusCheckAt[paymentId];
    if (lastCheckedAt != null &&
        now.difference(lastCheckedAt) < PaymentPollingPolicy.interval) {
      return _lastPaymentStatuses[paymentId] ?? 'pending';
    }

    final check = _fetchPaymentStatus(paymentId);
    _paymentStatusChecksInFlight[paymentId] = check;
    try {
      final status = await check;
      if (status != 'error') {
        _lastPaymentStatusCheckAt[paymentId] = DateTime.now();
        _lastPaymentStatuses[paymentId] = status;
      }
      return status;
    } catch (e) {
      print("Erro polling: $e");
      return 'error';
    } finally {
      if (identical(_paymentStatusChecksInFlight[paymentId], check)) {
        _paymentStatusChecksInFlight.remove(paymentId);
      }
    }
  }

  Future<String> _fetchPaymentStatus(String paymentId) async {
    try {
      final result = await _functions
          .httpsCallable('checkAndProcessPayment')
          .call({'paymentId': paymentId});
      return result.data['status']?.toString() ?? 'pending';
    } catch (e) {
      print("Erro polling: $e");
      return 'error';
    }
  }
}
