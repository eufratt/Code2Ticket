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

/// Isian jumlah desimal format Indonesia: titik ribuan otomatis, satu koma desimal (maks. 2 digit), kursor tetap
/// di tempatnya saat mengedit di tengah. Hanya angka dan koma yang diterima (titik hasil tempel dianggap pemisah ribuan).
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter({this.decimals = 2});

  /// Maks. digit desimal; 0 = bilangan bulat (koma ditolak), mis. IDR dan JPY.
  final int decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text, cursor = newValue.selection.baseOffset;
    final r = _format(raw, cursor, decimals);
    // Hapus mundur tepat di pemisah ribuan: tanpa ini teks kembali sama dan kursor macet; hapus angka di sebelahnya.
    if (r.text == oldValue.text && raw.length < oldValue.text.length && cursor > 0) {
      return _format(raw.substring(0, cursor - 1) + raw.substring(cursor), cursor - 1, decimals);
    }
    return r;
  }

  static TextEditingValue _format(String text, int cursor, int decimals) {
    final cur = cursor < 0 ? text.length : cursor.clamp(0, text.length);
    final buf = StringBuffer();
    var comma = false, sig = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final digit = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
      if (!digit && !(ch == ',' && !comma && decimals > 0)) continue;
      if (ch == ',') comma = true;
      buf.write(ch);
      if (i < cur) sig++;
    }
    final parts = buf.toString().split(',');
    var int = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (int.length > 15) int = int.substring(0, 15);
    if (int.isEmpty && comma) int = '0';
    final frac = parts.length > 1 ? parts[1].substring(0, parts[1].length.clamp(0, decimals)) : '';
    final plain = comma ? '$int,$frac' : int;
    final text2 = int.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.') + (comma ? ',$frac' : '');
    var left = sig > plain.length ? plain.length : sig, offset = 0;
    while (left > 0 && offset < text2.length) {
      if (text2[offset] != '.') left--;
      offset++;
    }
    return TextEditingValue(text: text2, selection: TextSelection.collapsed(offset: offset));
  }
}
