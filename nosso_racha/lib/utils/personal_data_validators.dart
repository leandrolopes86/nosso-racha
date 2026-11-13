import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();

    for (var index = 0; index < limitedDigits.length; index++) {
      if (index == 3 || index == 6) buffer.write('.');
      if (index == 9) buffer.write('-');
      buffer.write(limitedDigits[index]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();

    if (limitedDigits.isNotEmpty) {
      buffer.write('(');
      if (limitedDigits.length >= 2) {
        buffer.write('${limitedDigits.substring(0, 2)}) ');
        if (limitedDigits.length <= 6) {
          buffer.write(limitedDigits.substring(2));
        } else if (limitedDigits.length <= 10) {
          buffer.write(
            '${limitedDigits.substring(2, 6)}-${limitedDigits.substring(6)}',
          );
        } else {
          buffer.write(
            '${limitedDigits.substring(2, 7)}-${limitedDigits.substring(7)}',
          );
        }
      } else {
        buffer.write(limitedDigits);
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String formatCpf(String? value) => CpfInputFormatter()
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: value ?? ''),
    )
    .text;

String formatBrazilianPhone(String? value) => PhoneInputFormatter()
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: value ?? ''),
    )
    .text;

bool isValidCpf(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length != 11 || RegExp(r'^([0-9])\1{10}$').hasMatch(digits)) {
    return false;
  }

  int verifierDigit(int length) {
    var sum = 0;
    for (var index = 0; index < length; index++) {
      sum += int.parse(digits[index]) * (length + 1 - index);
    }
    final remainder = sum % 11;
    return remainder < 2 ? 0 : 11 - remainder;
  }

  return verifierDigit(9) == int.parse(digits[9]) &&
      verifierDigit(10) == int.parse(digits[10]);
}

bool isValidBrazilianPhone(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length == 10 || digits.length == 11;
}

DateTime? parseBirthDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final input = value.trim();
  try {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      return DateFormat('yyyy-MM-dd').parseStrict(input);
    }
    return DateFormat('dd/MM/yyyy').parseStrict(input);
  } on FormatException {
    return null;
  }
}

bool isAdult(DateTime? birthDate, {DateTime? today}) {
  if (birthDate == null) return false;
  final currentDate = today ?? DateTime.now();
  final eighteenthBirthday = DateTime(
    birthDate.year + 18,
    birthDate.month,
    birthDate.day,
  );
  return !eighteenthBirthday.isAfter(currentDate);
}

String birthDateForDisplay(String? value) {
  final date = parseBirthDate(value);
  return date == null ? '' : DateFormat('dd/MM/yyyy').format(date);
}

String birthDateForStorage(String value) {
  final date = parseBirthDate(value);
  if (date == null) return '';
  return DateFormat('yyyy-MM-dd').format(date);
}
