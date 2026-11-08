class PaymentPollingPolicy {
  static const interval = Duration(seconds: 30);

  static bool shouldPoll(Map<String, dynamic> payment, {DateTime? now}) {
    if (payment['type'] != 'mercadopago') return false;
    if (isTerminalStatus(payment['status']?.toString())) return false;

    final expiration = payment['expiration_date'];
    DateTime? expirationDate;
    if (expiration is DateTime) {
      expirationDate = expiration;
    } else if (expiration is String) {
      expirationDate = DateTime.tryParse(expiration);
    }

    return expirationDate != null &&
        (now ?? DateTime.now()).isBefore(expirationDate);
  }

  static bool isTerminalStatus(String? status) => const {
    'approved',
    'rejected',
    'cancelled',
    'canceled',
    'refunded',
    'charged_back',
    'expired',
  }.contains(status);
}
