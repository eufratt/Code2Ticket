import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../auth/data/datasources/auth_remote_data_source.dart';
import '../../../auth/services/password_hasher.dart';
import '../../domain/models/ticket_model.dart';
import '../../domain/repositories/ticket_repository.dart';
import '../datasources/ticket_remote_data_source.dart';

class TicketRepositoryImpl implements TicketRepository {
  final TicketRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final AuthRemoteDataSource authRemoteDataSource;
  final PasswordHasher _hasher;

  TicketRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.authRemoteDataSource,
    PasswordHasher? hasher,
  }) : _hasher = hasher ?? PasswordHasher();

  @override
  Future<List<TicketModel>> getUserTickets() async {
    final rawToken = await localDataSource.getSessionToken();
    if (rawToken == null || rawToken.isEmpty) {
      return [];
    }

    final tokenHash = _hasher.hashSessionToken(rawToken);
    final sessionData = await authRemoteDataSource.getSessionWithUser(tokenHash);
    if (sessionData == null) {
      return [];
    }

    return await remoteDataSource.fetchUserTickets(sessionData.user.id);
  }

  @override
  Future<TicketModel?> getTicketDetail(String ticketId) async {
    return await remoteDataSource.fetchTicketDetail(ticketId);
  }
}
