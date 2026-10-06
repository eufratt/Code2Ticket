import 'package:flutter/services.dart';

/// Formatter that automatically converts input to UPPERCASE and enforces
/// clean promo code formatting (format XXXX-XXXX-XXXX with auto-dash,
/// while also preserving custom hyphen placements like GAME-PKW-001).
class CodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Force uppercase and remove characters that are not alphanumeric or hyphen
    String text =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');

    // 2. If user is deleting (backspace), allow normal deletion without auto-adding dashes
    if (newValue.text.length < oldValue.text.length) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    // 3. Check whether hyphens are at custom positions (other than multiples of 4: 4, 9, 14, 19)
    bool hasCustomHyphen = false;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '-') {
        // In XXXX-XXXX-XXXX format, valid hyphen indices are 4, 9, 14, 19
        if (i != 4 && i != 9 && i != 14 && i != 19) {
          hasCustomHyphen = true;
          break;
        }
      }
    }

    // 4. Auto-dash: If continuous typing without custom hyphens, format into XXXX-XXXX-XXXX
    if (!hasCustomHyphen) {
      final raw = text.replaceAll('-', '');
      final buffer = StringBuffer();
      for (int i = 0; i < raw.length && i < 20; i++) {
        if (i > 0 && i % 4 == 0) {
          buffer.write('-');
        }
        buffer.write(raw[i]);
      }
      text = buffer.toString();
    }

    // 5. Limit maximum length to 24 characters
    if (text.length > 24) {
      text = text.substring(0, 24);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
