import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/main.dart';
import 'package:code2ticket/features/auth/domain/repositories/auth_repository.dart';
import 'package:code2ticket/features/auth/presentation/controllers/auth_controller.dart';
import 'package:code2ticket/features/auth/domain/models/user_model.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  Future<UserModel> register({required String username, required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<({UserModel user, String sessionToken})> login({required String identifier, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<UserModel?> validateStoredSession() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<String?> getStoredSessionToken() async => null;

  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<void> setBiometricEnabled(bool enabled) async {}
}

void main() {
  testWidgets('Code2TicketApp smoke test renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const Code2TicketApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Selamat Datang Kembali'), findsOneWidget);
    expect(find.text('Masuk Akun'), findsOneWidget);
  });
}
