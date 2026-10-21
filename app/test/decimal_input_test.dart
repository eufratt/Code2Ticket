import 'package:code2ticket/core/rupiah_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


// Isian Jumlah Konverter berpemisah ribuan.
const f = DecimalInputFormatter();

TextEditingValue type(String oldText, String newText, [int? cursor]) =>
    f.formatEditUpdate(TextEditingValue(text: oldText), TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: cursor ?? newText.length)));

void main() {
  group('DecimalInputFormatter', () {
    test('ribuan otomatis dan koma desimal', () {
      expect(type('', '1000000').text, '1.000.000');
      expect(type('', '25000').text, '25.000');
      expect(type('', '1234,56').text, '1.234,56');
      expect(type('', '0,').text, '0,');
      expect(type('', ',').text, '0,');
      expect(type('', '').text, '');
      expect(type('', '007').text, '7');
    });
    test('hanya angka dan satu koma; desimal maks. 2 digit', () {
      expect(type('', '1a2b').text, '12');
      expect(type('', '1,2,3').text, '1,23');
      expect(type('', '1,2345').text, '1,23');
      expect(type('', '-5').text, '5');
    });
    test('paste: polos dan sudah berformat', () {
      expect(type('', '1000000').text, '1.000.000');
      expect(type('', '1.234,56').text, '1.234,56');
    });
    test('hapus: angka dihapus meregrup; hapus di titik ribuan menghapus angka di sebelahnya', () {
      expect(type('1.234', '1.23', 4).text, '123');
      final r = type('1.234', '1234', 1); // titik terhapus, kursor setelah "1"
      expect(r.text, '234');
      expect(r.selection.baseOffset, 0);
    });
    test('kursor tidak melompat ke akhir saat menyisip di tengah', () {
      final r = type('1.234', '19.234', 2); // ketik "9" setelah "1"
      expect(r.text, '19.234');
      expect(r.selection.baseOffset, 2);
      final g = type('999', '9999', 1); // sisip "9" di depan: titik muncul, kursor setelah digit pertama
      expect(g.text, '9.999');
      expect(g.selection.baseOffset, 1);
    });
  });
}
