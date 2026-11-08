import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../models/payment_config_model.dart';
import 'payment_strategy.dart';

class ManualPaymentStrategy implements PaymentStrategy {
  @override
  Future<Map<String, dynamic>> generatePix({
    required EventModel event,
    required UserModel payer,
    required PaymentConfigModel config,
  }) async {
    // No modo manual, não geramos QR Code dinâmico via API.
    // Retornamos os dados estáticos simulando a estrutura de resposta para a UI não quebrar.
    
    if (config.manualPixKey.isEmpty) {
      throw Exception("Chave PIX manual não configurada.");
    }

    return {
      'type': 'manual',
      'qr_code': config.manualPixKey, // A chave é o "copia e cola"
      'qr_code_base64': null, // Sem imagem gerada automaticamente
      'payment_id': 'manual_${DateTime.now().millisecondsSinceEpoch}',
      'status': 'pending',
      'beneficiary': config.manualBeneficiary,
      'bank': config.manualBankName,
    };
  }

  @override
  Future<void> refundPix(String paymentId, PaymentConfigModel config) async {
    // Manual não faz estorno automático via API.
    // Apenas retorna sucesso para o app seguir o fluxo de registro no banco de dados.
    return; 
  }
}