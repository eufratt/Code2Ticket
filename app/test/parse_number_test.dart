import 'package:code2ticket/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseIdNumber: format Indonesia', () {
    const ok = {
      '1.000': 1000.0, '1.000.000,50': 1000000.5, '1,5': 1.5, '1.5': 1.5, '12': 12.0, '0': 0.0, '0,5': 0.5,
      '0.500': 0.5, '100.000': 100000.0, '12.34': 12.34, '1.234,5': 1234.5, ' 7 ': 7.0, '1.2345': 1.2345,
    };
    ok.forEach((k, v) => expect(parseIdNumber(k), v, reason: k));
  });
  test('parseIdNumber: ditolak', () {
    for (final s in ['', '  ', 'abc', '-5', '-1.000', 'Infinity', 'NaN', '1e5', '1,2,3', '1.0000.000', '1,', '1.', ',5', '.5', '1,000.5', '12.3.4', '1.000,5,1', '1e999', '9' * 400]) {
      expect(parseIdNumber(s), isNull, reason: s);
    }
  });
}
