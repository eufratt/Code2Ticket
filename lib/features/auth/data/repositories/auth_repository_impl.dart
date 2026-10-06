// ignore_for_file: prefer_initializing_formals
import '../../domain/models/user_model.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/password_hasher.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final PasswordHasher _hasher;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
    PasswordHasher? hasher,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource,
        _hasher = hasher ?? PasswordHasher();

  @override
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  }) async {
    // 1. Format Validations
    final trimmedUsername = username.trim();
    final trimmedEmail = email.trim();

    if (trimmedUsername.length < 3) {
      throw const FormatException('Username minimal harus 3 karakter.');
    }
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(trimmedUsername)) {
      throw const FormatException('Username hanya boleh berisi huruf, angka, titik, dan garis bawah.');
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(trimmedEmail)) {
      throw const FormatException('Format email tidak valid.');
    }

    if (password.length < 8) {
      throw const FormatException('Kata sandi minimal harus 8 karakter.');
    }

    // 2. Check Uniqueness
    final exists = await _remoteDataSource.checkUserExists(
      username: trimmedUsername,
      email: trimmedEmail,
    );
    if (exists) {
      throw const FormatException('Username atau email sudah terdaftar. Silakan gunakan yang lain.');
    }

    // 3. Hash Password using BCrypt (with 10 rounds of salt)
    final passwordHash = _hasher.hashPassword(password);

    // 4. Save to Database
    final newUser = await _remoteDataSource.createUser(
      username: trimmedUsername,
      email: trimmedEmail,
      passwordHash: passwordHash,
    );

    await _remoteDataSource.logActivity(
      userId: newUser.id,
      activityType: 'REGISTER',
      description: 'Pendaftaran akun baru berhasil.',
    );

    return newUser;
  }

  @override
  Future<({UserModel user, String sessionToken})> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty) {
      throw const FormatException('Username atau email tidak boleh kosong.');
    }
    if (password.isEmpty) {
      throw const FormatException('Kata sandi tidak boleh kosong.');
    }

    // 1. Fetch User by Username or Email
    final userRow = await _remoteDataSource.findUserByIdentifier(cleanIdentifier);
    if (userRow == null) {
      throw const FormatException('Pengguna dengan username atau email tersebut tidak ditemukan.');
    }

    final storedHash = userRow['password_hash'] as String?;
    if (storedHash == null || !_hasher.verifyPassword(password, storedHash)) {
      throw const FormatException('Kata sandi yang Anda masukkan salah.');
    }

    final user = UserModel.fromJson(userRow);

    // 2. Generate Cryptographically Secure 32-byte Session Token
    final rawToken = _hasher.generateSessionToken();
    final tokenHash = _hasher.hashSessionToken(rawToken);

    // 3. 7 Days Expiry
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 7));

    // 4. Save Session Hash into Database
    await _remoteDataSource.createSession(
      userId: user.id,
      tokenHash: tokenHash,
      expiresAt: expiresAt,
    );

    // 5. Store Raw Token in Flutter Secure Storage
    await _localDataSource.saveSessionToken(rawToken);
    await _localDataSource.saveLastIdentifier(cleanIdentifier);

    // 6. Log Activity
    await _remoteDataSource.logActivity(
      userId: user.id,
      activityType: 'LOGIN',
      description: 'Pengguna berhasil masuk (login).',
    );

    return (user: user, sessionToken: rawToken);
  }

  @override
  Future<UserModel?> validateStoredSession() async {
    final rawToken = await _localDataSource.getSessionToken();
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }

    final tokenHash = _hasher.hashSessionToken(rawToken);
    final sessionData = await _remoteDataSource.getSessionWithUser(tokenHash);

    if (sessionData == null) {
      await _localDataSource.clearSessionToken();
      return null;
    }

    if (!sessionData.session.isValid) {
      await _localDataSource.clearSessionToken();
      return null;
    }

    return sessionData.user;
  }

  @override
  Future<void> logout() async {
    final rawToken = await _localDataSource.getSessionToken();
    if (rawToken != null && rawToken.isNotEmpty) {
      final tokenHash = _hasher.hashSessionToken(rawToken);
      try {
        await _remoteDataSource.revokeSession(tokenHash);
      } catch (_) {}
    }
    await _localDataSource.clearSessionToken();
  }

  @override
  Future<String?> getStoredSessionToken() async {
    return await _localDataSource.getSessionToken();
  }

  @override
  Future<bool> isBiometricEnabled() async {
    return await _localDataSource.isBiometricEnabled();
  }

  @override
  Future<void> setBiometricEnabled(bool enabled) async {
    await _localDataSource.setBiometricEnabled(enabled);
  }
}
