enum DiscoverSort {
  deadlineAsc('Draw Terdekat'),
  prizeDesc('Hadiah Tertinggi'),
  prizeAsc('Hadiah Terendah'),
  newest('Terbaru');

  final String label;
  const DiscoverSort(this.label);
}

class DiscoverFilterModel {
  final String query;
  final String category;
  final DiscoverSort sort;
  final double? maxRadiusKm;
  final bool? onlyGeoRestricted; // null: all, true: only local, false: only national
  final double? minPrizeUsd;
  final double? maxPrizeUsd;

  const DiscoverFilterModel({
    this.query = '',
    this.category = 'Semua',
    this.sort = DiscoverSort.deadlineAsc,
    this.maxRadiusKm,
    this.onlyGeoRestricted,
    this.minPrizeUsd,
    this.maxPrizeUsd,
  });

  bool get hasActiveFilter =>
      query.isNotEmpty ||
      category != 'Semua' ||
      sort != DiscoverSort.deadlineAsc ||
      maxRadiusKm != null ||
      onlyGeoRestricted != null ||
      minPrizeUsd != null ||
      maxPrizeUsd != null;

  DiscoverFilterModel copyWith({
    String? query,
    String? category,
    DiscoverSort? sort,
    double? maxRadiusKm,
    bool? Function()? onlyGeoRestricted,
    double? minPrizeUsd,
    double? maxPrizeUsd,
  }) {
    return DiscoverFilterModel(
      query: query ?? this.query,
      category: category ?? this.category,
      sort: sort ?? this.sort,
      maxRadiusKm: maxRadiusKm ?? this.maxRadiusKm,
      onlyGeoRestricted: onlyGeoRestricted != null ? onlyGeoRestricted() : this.onlyGeoRestricted,
      minPrizeUsd: minPrizeUsd ?? this.minPrizeUsd,
      maxPrizeUsd: maxPrizeUsd ?? this.maxPrizeUsd,
    );
  }

  static const List<String> availableCategories = [
    'Semua',
    'Tech',
    'Gaming',
    'Travel',
    'Food',
    'Automotive',
    'Lifestyle',
  ];
}
