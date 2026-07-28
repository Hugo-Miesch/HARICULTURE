import 'package:flutter/services.dart';

List<TextInputFormatter> get serialNumberInputFormatters => [
      const _UppercaseTextInputFormatter(),
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
      LengthLimitingTextInputFormatter(4),
    ];

String normalizeSerialNumber(String value) => value.trim().toUpperCase();

class _UppercaseTextInputFormatter extends TextInputFormatter {
  const _UppercaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      composing: TextRange.empty,
    );
  }
}
