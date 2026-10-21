import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/display.dart';

// Nama Profil terpusat.
void main() {
  group('Profil: nama terpusat', () {
    Future<void> pump(WidgetTester tester, String name, {double scale = 1, Brightness b = Brightness.light}) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearAllTestValues();
      });
      final api = FakeApi((m, p, bd) async => {'ok': true});
      final auth = FakeAuth(api)
        ..user = AppUser(id: 'u1', username: 'eufrat', email: 'e@x.id', fullName: name, role: 'user', xp: 1, level: 1);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
          ...displayProviders(),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: b),
          home: ProfileScreen(picker: (_) async => null, compress: (x) async => x),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final (label, name, scale, bright) in [
      ('pendek', 'budii dub', 1.0, Brightness.light),
      ('pendek gelap font besar', 'budii dub', 1.5, Brightness.dark),
      ('100 karakter', 'Nama Panjang ' * 7 + 'abcdefghi', 1.0, Brightness.light),
      ('100 karakter font besar gelap', 'Nama Panjang ' * 7 + 'abcdefghi', 1.5, Brightness.dark),
    ]) {
      testWidgets('$label: teks nama di tengah layar, sejajar @username, tanpa overflow, pensil >= 48 dp', (tester) async {
        await pump(tester, name, scale: scale, b: bright);
        final screen = tester.getSize(find.byType(MaterialApp)).width / 2;
        expect(tester.getCenter(find.byKey(const Key('profile_name'))).dx, closeTo(screen, 1));
        expect(tester.getCenter(find.text('@eufrat')).dx, closeTo(screen, 1));
        final pencil = tester.getRect(find.byKey(const Key('edit_name')));
        expect(pencil.width, greaterThanOrEqualTo(48));
        expect(pencil.height, greaterThanOrEqualTo(48));
        expect(tester.getRect(find.byKey(const Key('profile_name'))).right, lessThanOrEqualTo(pencil.left + 0.5));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
