import '../models/discover_filter_model.dart';
import '../models/giveaway_model.dart';

abstract class DiscoverRepository {
  Future<List<GiveawayModel>> getGiveaways({
    DiscoverFilterModel? filter,
    double? userLat,
    double? userLng,
  });
}
