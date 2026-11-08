import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/services/payment/payment_polling_policy.dart';

void main() {
  group('PaymentPollingPolicy', () {
    final now = DateTime(2026, 11, 8, 15);

    test('polls only non-terminal Mercado Pago payments before expiry', () {
      expect(
        PaymentPollingPolicy.shouldPoll({
          'type': 'mercadopago',
          'status': 'pending',
          'expiration_date': now
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        }, now: now),
        isTrue,
      );
    });

    test('does not poll manual, expired, or terminal payments', () {
      expect(
        PaymentPollingPolicy.shouldPoll({
          'type': 'manual',
          'status': 'pending',
        }, now: now),
        isFalse,
      );
      expect(
        PaymentPollingPolicy.shouldPoll({
          'type': 'mercadopago',
          'status': 'pending',
          'expiration_date': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        }, now: now),
        isFalse,
      );
      expect(
        PaymentPollingPolicy.shouldPoll({
          'type': 'mercadopago',
          'status': 'approved',
        }, now: now),
        isFalse,
      );
      expect(
        PaymentPollingPolicy.shouldPoll({
          'type': 'mercadopago',
          'status': 'pending',
        }, now: now),
        isFalse,
      );
      expect(PaymentPollingPolicy.isTerminalStatus('rejected'), isTrue);
    });
  });
}
