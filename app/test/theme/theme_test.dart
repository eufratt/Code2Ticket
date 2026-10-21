import 'dart:math' as math;

import 'package:code2ticket/core/theme/app_colors.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/core/theme/category_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (name, c) in [('terang', AppColors.light), ('gelap', AppColors.dark)]) {
    group('kontras tema $name (DESIGN.md 7: teks >= 4,5:1)', () {
      final pairs = <String, (Color, Color)>{
        'teks utama / background': (c.onBackground, c.background),
        'teks utama / surface': (c.onBackground, c.surface),
        'teks utama / surfaceVariant': (c.onBackground, c.surfaceVariant),
        'teks sekunder / background': (c.muted, c.background),
        'teks sekunder / surface': (c.muted, c.surface),
        'teks sekunder pada kolom input': (c.mutedOnVariant, c.surfaceVariant),
        'teks tombol utama': (c.onPrimary, c.primary),
        'primary sebagai teks / surface': (c.primary, c.surface),
        'primary sebagai teks / background': (c.primary, c.background),
        'teks pada primaryContainer': (c.onPrimaryContainer, c.primaryContainer),
        'teks amber kecil / surface': (c.accentText, c.surface),
        'teks amber kecil / background': (c.accentText, c.background),
        'teks di atas amber': (c.onAccent, c.accent),
        'teks hijau / surface': (c.successText, c.surface),
        'teks error / surface': (c.error, c.surface),
        'teks error / background': (c.error, c.background),
        'teks pada errorContainer': (c.onErrorContainer, c.errorContainer),
        'chip sukses': (c.statusSuccess.fg, c.statusSuccess.bg),
        'chip peringatan': (c.statusWarning.fg, c.statusWarning.bg),
        'chip error': (c.statusError.fg, c.statusError.bg),
        'chip info': (c.statusInfo.fg, c.statusInfo.bg),
        'chip netral': (c.statusNeutral.fg, c.statusNeutral.bg),
      };
      pairs.forEach((label, p) {
        test(label, () => expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: label));
      });
    });

    group('kontras border non-teks tema $name (WCAG 1.4.11: border >= 3:1)', () {
      final nonTextPairs = <String, (Color, Color)>{
        'border komponen (outline) / background': (c.outline, c.background),
        'border komponen (outline) / surface': (c.outline, c.surface),
        'border komponen (outline) / surfaceVariant': (c.outline, c.surfaceVariant),
      };
      nonTextPairs.forEach((label, p) {
        test(label, () => expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(3.0), reason: label));
      });
    });
  }

  testWidgets('kedua tema membawa token dan mengikuti kecerahan', (tester) async {
    final l = AppTheme.light(), d = AppTheme.dark();
    expect(l.brightness, Brightness.light);
    expect(d.brightness, Brightness.dark);
    expect(l.extension<AppColors>()!.isDark, isFalse);
    expect(d.extension<AppColors>()!.isDark, isTrue);
    expect(l.colorScheme.primary, const Color(0xFF4F46E5));
    expect(d.colorScheme.primary, const Color(0xFF818CF8));
    expect(l.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    expect(d.scaffoldBackgroundColor, const Color(0xFF0F172A));
  });

  test('kategori backend dipetakan ke gaya DESIGN.md; tak dikenal = lainnya', () {
    expect(CategoryStyle.of('gaming').key, 'gaming');
    expect(CategoryStyle.of('tech').key, 'elektronik');
    expect(CategoryStyle.of('food').key, 'makanan');
    expect(CategoryStyle.of('travel').key, 'travel');
    expect(CategoryStyle.of('fashion').key, 'fashion');
    expect(CategoryStyle.of('lifestyle').key, 'lainnya');
    expect(CategoryStyle.of('other').key, 'lainnya');
    expect(CategoryStyle.of('xyz').key, 'lainnya');
    expect(CategoryStyle.of(null).key, 'lainnya');
  });

  for (final (name, theme) in [('terang', AppTheme.light()), ('gelap', AppTheme.dark())]) {
    testWidgets('komponen form tema $name memenuhi ukuran minimum (tinggi >= 56 dp)', (tester) async {
      expect(theme.inputDecorationTheme.constraints?.minHeight, greaterThanOrEqualTo(56.0));
      final padding = theme.inputDecorationTheme.contentPadding?.vertical ?? 0;
      expect(padding, greaterThanOrEqualTo(32.0)); // vertikal 16 dp atas + 16 dp bawah

      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('tf'), decoration: InputDecoration(labelText: 'Label')),
              DropdownButtonFormField<String>(
                key: const Key('dd'),
                isExpanded: true,
                initialValue: 'A',
                decoration: const InputDecoration(labelText: 'Dropdown'),
                items: const [DropdownMenuItem(value: 'A', child: Text('Opsi A'))],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final tfSize = tester.getSize(find.byKey(const Key('tf')));
      final ddSize = tester.getSize(find.byKey(const Key('dd')));
      expect(tfSize.height, greaterThanOrEqualTo(56.0));
      expect(ddSize.height, greaterThanOrEqualTo(56.0));
    });
  }
}
