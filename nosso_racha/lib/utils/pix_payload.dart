import 'dart:convert';

class PixPayload {
  static String build({
    required String pixKey,
    required String receiverName,
    double? amount,
  }) {
    final normalizedKey = pixKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(pixKey, 'pixKey', 'A chave Pix é obrigatória.');
    }
    if (amount != null && (!amount.isFinite || amount <= 0)) {
      throw ArgumentError.value(amount, 'amount', 'O valor deve ser positivo.');
    }

    final merchantAccount =
        _field('00', 'br.gov.bcb.pix') + _field('01', normalizedKey);
    final payload = [
      _field('00', '01'),
      _field('01', '11'),
      _field('26', merchantAccount),
      _field('52', '0000'),
      _field('53', '986'),
      if (amount != null) _field('54', amount.toStringAsFixed(2)),
      _field('58', 'BR'),
      _field('59', _truncateUtf8(receiverName.trim().toUpperCase(), 25)),
      _field('60', 'BRASIL'),
      _field('62', _field('05', '***')),
      '6304',
    ].join();

    return '$payload${_crc16(payload)}';
  }

  static String _field(String id, String value) {
    final length = utf8.encode(value).length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  static String _truncateUtf8(String value, int maxBytes) {
    final result = StringBuffer();
    var usedBytes = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final length = utf8.encode(character).length;
      if (usedBytes + length > maxBytes) break;
      result.write(character);
      usedBytes += length;
    }
    return result.toString();
  }

  static String _crc16(String value) {
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
}
