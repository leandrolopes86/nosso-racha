class PaymentConfigModel {
  final String provider; // 'manual', 'mercadopago', etc.
  final bool isActive;
  final String accessToken; // MP Access Token
  final String publicKey; // MP Public Key
  
  // Dados do Manual (Legado/Backup)
  final String manualPixKey;
  final String manualBeneficiary;
  final String manualBankName; // <--- NOVO CAMPO

  PaymentConfigModel({
    required this.provider,
    required this.isActive,
    this.accessToken = '',
    this.publicKey = '',
    this.manualPixKey = '',
    this.manualBeneficiary = '',
    this.manualBankName = '', // <--- NOVO
  });

  factory PaymentConfigModel.fromMap(Map<String, dynamic> data) {
    return PaymentConfigModel(
      provider: data['provider'] ?? 'manual',
      isActive: data['is_active'] ?? true,
      accessToken: data['access_token'] ?? '',
      publicKey: data['public_key'] ?? '',
      manualPixKey: data['manual_pix_key'] ?? '',
      manualBeneficiary: data['manual_beneficiary'] ?? '',
      manualBankName: data['manual_bank_name'] ?? '', // <--- LER
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'provider': provider,
      'is_active': isActive,
      'access_token': accessToken,
      'public_key': publicKey,
      'manual_pix_key': manualPixKey,
      'manual_beneficiary': manualBeneficiary,
      'manual_bank_name': manualBankName, // <--- SALVAR
    };
  }
}