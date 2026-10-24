import 'package:code2ticket/features/chat/inline_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bold lalu teks biasa', () {
    expect(parseInlineBold('**a** b'), const [BoldSpan('a', bold: true), BoldSpan(' b')]);
  });
  test('tanpa tanda tetap sama', () {
    expect(parseInlineBold('halo dunia'), const [BoldSpan('halo dunia')]);
  });
  test('tidak ditutup tetap utuh', () {
    expect(parseInlineBold('**tidak ditutup'), const [BoldSpan('**tidak ditutup')]);
  });
  test('beberapa pasang', () {
    expect(parseInlineBold('x **a** y **b** z'), const [
      BoldSpan('x '), BoldSpan('a', bold: true), BoldSpan(' y '), BoldSpan('b', bold: true), BoldSpan(' z'),
    ]);
  });
  test('bintang tunggal dan # dibiarkan', () {
    expect(parseInlineBold('# a * b'), const [BoldSpan('# a * b')]);
  });
}
