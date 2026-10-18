import 'dart:math' as math;

/// Jarak haversine dalam km (R = 6371), rumus yang sama dengan backend (GET /giveaways).
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
  return 2 * 6371.0 * math.asin(math.sqrt(math.min(1.0, a.toDouble())));
}
