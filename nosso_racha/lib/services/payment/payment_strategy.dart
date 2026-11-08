import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../models/payment_config_model.dart';

abstract class PaymentStrategy {
  // Todo provedor deve saber gerar um PIX e retornar um Mapa padronizado
  Future<Map<String, dynamic>> generatePix({
    required EventModel event,
    required UserModel payer,
    required PaymentConfigModel config,
  });

  // Todo provedor (automático) deve saber estornar. 
  // O Manual pode apenas lançar uma exceção ou não fazer nada.
  Future<void> refundPix(String paymentId, PaymentConfigModel config);
}