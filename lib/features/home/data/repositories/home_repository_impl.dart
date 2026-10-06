import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../auth/data/datasources/auth_remote_data_source.dart';
import '../../../auth/services/password_hasher.dart';
import '../../domain/models/home_summary_model.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_remote_data_source.dart';

class HomeRepositoryImpl implements HomeRepository {
  final HomeRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final AuthRemoteDataSource authRemoteDataSource;
  final PasswordHasher _hasher;

  HomeRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.authRemoteDataSource,
    PasswordHasher? hasher,
  }) : _hasher = hasher ?? PasswordHasher();

  @override
  Future<HomeSummaryModel> getHomeSummary() async {
    String? userId;
    try {
      final rawToken = await localDataSource.getSessionToken();
      if (rawToken != null && rawToken.isNotEmpty) {
        final tokenHash = _hasher.hashSessionToken(rawToken);
        final session = await authRemoteDataSource.getSessionWithUser(tokenHash);
        userId = session?.user.id;
      }
    } catch (_) {}

    return await remoteDataSource.fetchHomeSummary(userId);
  }
}
