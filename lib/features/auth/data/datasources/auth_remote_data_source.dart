import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/session_model.dart';
import '../../domain/models/user_model.dart';

class AuthRemoteDataSource {
  final SupabaseClient _client;

  AuthRemoteDataSource(this._client);

  /// Fetches a user by username or email.
  Future<Map<String, dynamic>?> findUserByIdentifier(String identifier) async {
    final clean = identifier.trim().toLowerCase();
    final response = await _client
        .from('users')
        .select()
        .or('email.ilike.$clean,username.ilike.$clean')
        .maybeSingle();

    return response;
  }

  /// Checks if username or email already exists.
  Future<bool> checkUserExists({
    required String username,
    required String email,
  }) async {
    final response = await _client
        .from('users')
        .select('id')
        .or('username.ilike.${username.trim()},email.ilike.${email.trim()}')
        .limit(1);

    return (response as List).isNotEmpty;
  }

  /// Inserts a new user record, initial game score, and welcome notification.
  Future<UserModel> createUser({
    required String username,
    required String email,
    required String passwordHash,
  }) async {
    final userRow = await _client.from('users').insert({
      'username': username.trim().toLowerCase(),
      'email': email.trim().toLowerCase(),
      'password_hash': passwordHash,
    }).select().single();

    final user = UserModel.fromJson(userRow);

    // Seed initial game scores for the user
    try {
      await _client.from('game_scores').insert({
        'user_id': user.id,
        'score': 0,
        'xp': 0,
        'badge': 'Pemula',
        'level': 1,
      });
    } catch (_) {}

    // Seed welcome notification
    try {
      await _client.from('notifications').insert({
        'user_id': user.id,
        'title': 'Selamat Datang di Code2Ticket!',
        'message': 'Akun Anda berhasil didaftarkan. Tukarkan kode campaign pertamamu dan menangkan hadiah undian digital!',
        'type': 'system',
      });
    } catch (_) {}

    return user;
  }

  /// Inserts a newly generated session into the sessions table.
  Future<SessionModel> createSession({
    required String userId,
    required String tokenHash,
    required DateTime expiresAt,
  }) async {
    final sessionRow = await _client.from('sessions').insert({
      'user_id': userId,
      'token_hash': tokenHash,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'revoked': false,
    }).select().single();

    return SessionModel.fromJson(sessionRow);
  }

  /// Finds a session by its SHA-256 token hash along with user information.
  Future<({SessionModel session, UserModel user})?> getSessionWithUser(String tokenHash) async {
    final sessionRow = await _client
        .from('sessions')
        .select('*, users(*)')
        .eq('token_hash', tokenHash)
        .eq('revoked', false)
        .maybeSingle();

    if (sessionRow == null) return null;

    final session = SessionModel.fromJson(sessionRow);
    final userMap = sessionRow['users'] as Map<String, dynamic>?;
    if (userMap == null) return null;

    final user = UserModel.fromJson(userMap);
    return (session: session, user: user);
  }

  /// Marks a session as revoked in the database.
  Future<void> revokeSession(String tokenHash) async {
    await _client
        .from('sessions')
        .update({'revoked': true})
        .eq('token_hash', tokenHash);
  }

  /// Records user activity log.
  Future<void> logActivity({
    required String userId,
    required String activityType,
    required String description,
  }) async {
    try {
      await _client.from('user_activity').insert({
        'user_id': userId,
        'activity_type': activityType,
        'description': description,
      });
    } catch (_) {}
  }
}
