import '../models/home_summary_model.dart';

abstract class HomeRepository {
  /// Fetches home dashboard summary data: user tickets count,
  /// nearest live draw with countdown, recommended draws, and nearby draws.
  Future<HomeSummaryModel> getHomeSummary({
    double? userLat,
    double? userLng,
  });
}
