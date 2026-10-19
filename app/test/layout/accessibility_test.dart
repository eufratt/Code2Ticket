import 'package:code2ticket/features/auth/biometric_lock_screen.dart';
import 'package:code2ticket/features/auth/login_screen.dart';
import 'package:code2ticket/features/auth/register_screen.dart';
import 'package:code2ticket/features/converter/converter_screen.dart';
import 'package:code2ticket/features/feedback/feedback_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:code2ticket/features/profile/settings_screen.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:code2ticket/features/tickets/tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui.dart';
import 'screens_layout_test.dart' show SampleEnv, sampleGiveaways;

/// DESIGN.md bagian 7: target sentuh >= 48 dp, tombol berlabel (Semantics), kontras teks, di kedua tema.
void main() {
  final screens = <String, Widget Function()>{
    'Home': () => const HomeScreen(),
    'Detail Giveaway': () => GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse(sampleGiveaways().first)),
    'My Tickets': () => const TicketsScreen(),
    'Profil': () => const ProfileScreen(),
    'Login': () => const LoginScreen(),
    'Daftar': () => const RegisterScreen(),
    'Kunci biometric': () => const BiometricLockScreen(),
    'Konverter': () => const ConverterScreen(),
    'Pengaturan': () => const SettingsScreen(),
    'Saran & Kesan': () => const FeedbackScreen(),
    'Input Code': () => const InputCodeScreen(),
  };

  for (final brightness in [Brightness.light, Brightness.dark]) {
    group('aksesibilitas, tema ${brightness.name}', () {
      for (final e in screens.entries) {
        testWidgets(e.key, (tester) async {
          await setViewport(tester, height: 1600, brightness: brightness);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(SampleEnv().app(e.value()));
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
        });
      }
    });
  }
}
