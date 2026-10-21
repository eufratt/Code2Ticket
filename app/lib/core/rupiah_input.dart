import 'package:flutter/services.dart';

/// Rupiah bulat dari teks berpemisah ribuan ("5.000.000" atau "5000000"); null bila kosong atau bukan angka bulat.
int? parseRupiah(String text) {
  final digits = text.trim().replaceAll('.', '');
  if (digits.isEmpty || digits.length > 15 || !RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
  return int.parse(digits);
}

/// Isian rupiah: hanya angka, pemisah ribuan "." otomatis saat mengetik ("5000000" -> "5.000.000"), maks. 12 digit.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    final text = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
