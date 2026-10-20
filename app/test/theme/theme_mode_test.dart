import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../support/display.dart';

void main() {
  group('SettingsController.themeMode', () {
    test('bawaan = ikuti sistem', () async {
      final s = SettingsController(MemorySettings());
      expect(s.themeMode, ThemeMode.system);
      await s.load();
      expect(s.themeMode, ThemeMode.system);
    });

    test('memilih Gelap mengubah themeMode dan memberi tahu pendengar', () async {
      final s = SettingsController(MemorySettings());
      var notified = 0;
      s.addListener(() => notified++);
      await s.setThemeMode(ThemeMode.dark);
      expect(s.themeMode, ThemeMode.dark);
      expect(notified, 1);
    });

    test('pilihan tersimpan dan terbaca ulang oleh controller baru', () async {
      final store = MemorySettings();
      await SettingsController(store).setThemeMode(ThemeMode.dark);
      final again = SettingsController(store);
      await again.load();
      expect(again.themeMode, ThemeMode.dark);
    });

    test('nilai tersimpan tak dikenal jatuh ke ikuti sistem', () async {
      final store = MemorySettings()..values['|${SettingsController.themeKey}'] = 'ungu';
      final s = SettingsController(store);
      await s.load();
      expect(s.themeMode, ThemeMode.system);
    });
  });

  testWidgets('Profil: item Tema membuka dialog, memilih Gelap langsung berlaku', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = FakeApi((m, p, b) async => {'ok': true});
    final auth = FakeAuth(api)
      ..user = AppUser(id: 'u1', username: 'e', email: 'e@x.id', fullName: 'E', role: 'user', xp: 0, level: 1, badges: const []);
    final settings = SettingsController(MemorySettings());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
        ...displayProviders(settings: settings),
      ],
      child: Builder(
        builder: (context) => MaterialApp(themeMode: context.watch<SettingsController>().themeMode, darkTheme: ThemeData.dark(), home: const ProfileScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('open_theme')));
    await tester.pumpAndSettle();
    expect(find.text('Ikuti sistem'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open_theme')));
    await tester.pumpAndSettle();
    for (final l in ['Ikuti sistem', 'Terang', 'Gelap']) {
      expect(find.text(l), findsWidgets);
    }
    await tester.tap(find.byKey(const Key('theme_dark')));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(ProfileScreen))).brightness, Brightness.dark);
  });
}
