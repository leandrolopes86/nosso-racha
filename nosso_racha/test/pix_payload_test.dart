import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/utils/pix_payload.dart';

void main() {
  test('builds a Pix BR Code payload with amount and valid CRC', () {
    final payload = PixPayload.build(
      pixKey: 'goleiro@example.com',
      receiverName: 'João Goleiro',
      amount: 40,
    );

    expect(payload, contains('goleiro@example.com'));
    expect(payload, contains('540540.00'));
    expect(
      payload.substring(payload.length - 4),
      _crc16(payload.substring(0, payload.length - 4)),
    );
  });

  test('builds a Pix BR Code payload without a fixed amount', () {
    final payload = PixPayload.build(
      pixKey: 'goleiro@example.com',
      receiverName: 'João Goleiro',
    );

    expect(payload, contains('goleiro@example.com'));
    expect(payload, contains('53039865802BR'));
    expect(
      payload.substring(payload.length - 4),
      _crc16(payload.substring(0, payload.length - 4)),
    );
  });

  test('rejects empty keys and non-positive amounts', () {
    expect(
      () => PixPayload.build(pixKey: ' ', receiverName: 'Goleiro', amount: 40),
      throwsArgumentError,
    );
    expect(
      () => PixPayload.build(
        pixKey: 'goleiro@example.com',
        receiverName: 'Goleiro',
        amount: 0,
      ),
      throwsArgumentError,
    );
  });
}

String _crc16(String value) {
  var crc = 0xFFFF;
  for (final byte in utf8.encode(value)) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}
