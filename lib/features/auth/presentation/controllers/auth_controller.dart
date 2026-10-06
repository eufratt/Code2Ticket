import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/supabase_client.dart';
import '../../data/datasources/auth_local_data_source.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/biometric_service.dart';
import 'auth_state.dart';

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) {
  return const AuthLocalDataSource();
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return AuthRemoteDataSource(supabase);
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final local = ref.watch(authLocalDataSourceProvider);
  final remote = ref.watch(authRemoteDataSourceProvider);
  return AuthRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
  );
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;
  late final BiometricService _biometricService;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    _biometricService = ref.watch(biometricServiceProvider);
    return const AuthInitial();
  }

  /// Checks stored session token validity on application startup.
  Future<void> checkSession() async {
    state = const AuthLoading('Memeriksa sesi...');
    try {
      final user = await _repository.validateStoredSession();
      if (user != null) {
        final isBioEnabled = await _repository.isBiometricEnabled();
        final isBioAvailable = await _biometricService.isBiometricAvailable();

        if (isBioEnabled && isBioAvailable) {
          state = Authenticated(user: user, isBiometricRequired: true);
        } else {
          state = Authenticated(user: user, isBiometricRequired: false);
        }
      } else {
        state = const Unauthenticated();
      }
    } catch (_) {
      state = const Unauthenticated();
    }
  }

  /// Prompts biometric unlock when app reopens with an active session.
  Future<bool> unlockWithBiometric() async {
    final current = state;
    if (current is! Authenticated) return false;

    final success = await _biometricService.authenticate();
    if (success) {
      state = current.copyWith(isBiometricRequired: false);
      return true;
    }
    return false;
  }

  /// Logs in using username or email and plain password.
  Future<bool> login(String identifier, String password) async {
    state = const AuthLoading('Memverifikasi akun...');
    try {
      final result = await _repository.login(
        identifier: identifier,
        password: password,
      );
      state = Authenticated(user: result.user, isBiometricRequired: false);
      return true;
    } catch (e) {
      final msg = e is FormatException ? e.message : e.toString();
      state = AuthError(msg);
      return false;
    }
  }

  /// Registers a new user account and automatically signs in upon success.
  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AuthLoading('Mendaftarkan akun baru...');
    try {
      await _repository.register(
        username: username,
        email: email,
        password: password,
      );

      // Auto login right after registration
      final result = await _repository.login(
        identifier: email,
        password: password,
      );
      state = Authenticated(user: result.user, isBiometricRequired: false);
      return true;
    } catch (e) {
      final msg = e is FormatException ? e.message : e.toString();
      state = AuthError(msg);
      return false;
    }
  }

  /// Logs out user, revokes session token in database, and clears local secure storage.
  Future<void> logout() async {
    state = const AuthLoading('Mengakhiri sesi...');
    try {
      await _repository.logout();
    } finally {
      state = const Unauthenticated();
    }
  }

  Future<bool> isBiometricEnabled() async {
    return await _repository.isBiometricEnabled();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _repository.setBiometricEnabled(enabled);
  }

  void resetError() {
    if (state is AuthError) {
      state = const Unauthenticated();
    }
  }
}
