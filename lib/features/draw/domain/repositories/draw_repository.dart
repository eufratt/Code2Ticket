import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';

abstract class DrawRepository {
  Future<List<GiveawayModel>> getDraws({String status = 'active'});
  Future<DrawDetailModel> getDrawDetail(String giveawayId);
}
