/// Potongan teks hasil [parseInlineBold].
class BoldSpan {
  const BoldSpan(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) => other is BoldSpan && other.text == text && other.bold == bold;
  @override
  int get hashCode => Object.hash(text, bold);
  @override
  String toString() => bold ? 'bold($text)' : 'plain($text)';
}

/// Mengubah pasangan **teks** menjadi potongan tebal (tanda bintang dibuang). Tanda tak berpasangan dibiarkan.
List<BoldSpan> parseInlineBold(String input) {
  final out = <BoldSpan>[];
  var i = 0;
  while (i < input.length) {
    final open = input.indexOf('**', i);
    final close = open < 0 ? -1 : input.indexOf('**', open + 2);
    if (open < 0 || close < 0 || close == open + 2) {
      out.add(BoldSpan(input.substring(i)));
      break;
    }
    if (open > i) out.add(BoldSpan(input.substring(i, open)));
    out.add(BoldSpan(input.substring(open + 2, close), bold: true));
    i = close + 2;
  }
  return out;
}
