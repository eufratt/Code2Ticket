import '../../domain/models/discover_filter_model.dart';
import '../../domain/models/giveaway_model.dart';

class DiscoverState {
  final bool isLoading;
  final List<GiveawayModel> giveaways;
  final DiscoverFilterModel filter;
  final String? errorMessage;
  final double? userLat;
  final double? userLng;

  const DiscoverState({
    this.isLoading = false,
    this.giveaways = const [],
    this.filter = const DiscoverFilterModel(),
    this.errorMessage,
    this.userLat,
    this.userLng,
  });

  DiscoverState copyWith({
    bool? isLoading,
    List<GiveawayModel>? giveaways,
    DiscoverFilterModel? filter,
    String? Function()? errorMessage,
    double? userLat,
    double? userLng,
  }) {
    return DiscoverState(
      isLoading: isLoading ?? this.isLoading,
      giveaways: giveaways ?? this.giveaways,
      filter: filter ?? this.filter,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      userLat: userLat ?? this.userLat,
      userLng: userLng ?? this.userLng,
    );
  }
}
