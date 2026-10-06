import '../../domain/models/discover_filter_model.dart';
import '../../domain/models/giveaway_model.dart';
import '../../domain/repositories/discover_repository.dart';
import '../datasources/discover_remote_data_source.dart';

class DiscoverRepositoryImpl implements DiscoverRepository {
  final DiscoverRemoteDataSource _remoteDataSource;

  const DiscoverRepositoryImpl(this._remoteDataSource);

  @override
  Future<List<GiveawayModel>> getGiveaways({
    DiscoverFilterModel? filter,
    double? userLat,
    double? userLng,
  }) async {
    final all = await _remoteDataSource.fetchGiveaways(
      userLat: userLat,
      userLng: userLng,
    );

    if (filter == null) {
      return all;
    }

    // 1. Search Query
    var filtered = all.where((item) {
      if (filter.query.isNotEmpty) {
        final q = filter.query.toLowerCase().trim();
        final matchTitle = item.title.toLowerCase().contains(q);
        final matchPrize = item.prizeName.toLowerCase().contains(q);
        final matchDesc = item.description?.toLowerCase().contains(q) ?? false;
        final matchCategory = item.category.toLowerCase().contains(q);
        if (!matchTitle && !matchPrize && !matchDesc && !matchCategory) {
          return false;
        }
      }

      // 2. Category
      if (filter.category != 'Semua') {
        if (item.category.toLowerCase() != filter.category.toLowerCase()) {
          return false;
        }
      }

      // 3. Location / Geo restriction
      if (filter.onlyGeoRestricted != null) {
        if (item.isGeoRestricted != filter.onlyGeoRestricted) {
          return false;
        }
      }

      // 4. Distance / Radius
      if (filter.maxRadiusKm != null && item.distanceKm != null) {
        if (item.distanceKm! > filter.maxRadiusKm!) {
          return false;
        }
      }

      // 5. Min Prize
      if (filter.minPrizeUsd != null) {
        if (item.prizeValueUsd < filter.minPrizeUsd!) {
          return false;
        }
      }

      // 6. Max Prize
      if (filter.maxPrizeUsd != null) {
        if (item.prizeValueUsd > filter.maxPrizeUsd!) {
          return false;
        }
      }

      return true;
    }).toList();

    // 7. Sort
    switch (filter.sort) {
      case DiscoverSort.deadlineAsc:
        filtered.sort((a, b) => a.drawAt.compareTo(b.drawAt));
        break;
      case DiscoverSort.prizeDesc:
        filtered.sort((a, b) => b.prizeValueUsd.compareTo(a.prizeValueUsd));
        break;
      case DiscoverSort.prizeAsc:
        filtered.sort((a, b) => a.prizeValueUsd.compareTo(b.prizeValueUsd));
        break;
      case DiscoverSort.newest:
        filtered.sort((a, b) => b.startAt.compareTo(a.startAt));
        break;
    }

    return filtered;
  }
}
