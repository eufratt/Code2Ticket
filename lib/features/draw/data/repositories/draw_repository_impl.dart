import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/data/datasources/draw_remote_data_source.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';
import 'package:code2ticket/features/draw/domain/repositories/draw_repository.dart';

class DrawRepositoryImpl implements DrawRepository {
  final DrawRemoteDataSource _remoteDataSource;

  const DrawRepositoryImpl(this._remoteDataSource);

  @override
  Future<List<GiveawayModel>> getDraws({String status = 'active'}) {
    return _remoteDataSource.fetchDraws(status: status);
  }

  @override
  Future<DrawDetailModel> getDrawDetail(String giveawayId) {
    return _remoteDataSource.fetchDrawDetail(giveawayId);
  }
}
