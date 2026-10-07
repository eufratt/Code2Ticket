import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/nominatim_service.dart';
import '../../../discover/domain/models/giveaway_model.dart';
import '../../../discover/presentation/controllers/discover_controller.dart';

class MapState {
  final UserLocation userLocation;
  final List<GiveawayModel> allGiveaways;
  final List<GiveawayModel> filteredGiveaways;
  final GiveawayModel? selectedGiveaway;
  final double? selectedRadiusKm; // null: all, or 5, 10, 15, 25 km
  final List<NominatimPlace> searchSuggestions;
  final bool isSearching;
  final bool isLoading;
  final String? errorMessage;

  const MapState({
    required this.userLocation,
    this.allGiveaways = const [],
    this.filteredGiveaways = const [],
    this.selectedGiveaway,
    this.selectedRadiusKm,
    this.searchSuggestions = const [],
    this.isSearching = false,
    this.isLoading = false,
    this.errorMessage,
  });

  MapState copyWith({
    UserLocation? userLocation,
    List<GiveawayModel>? allGiveaways,
    List<GiveawayModel>? filteredGiveaways,
    GiveawayModel? Function()? selectedGiveaway,
    double? Function()? selectedRadiusKm,
    List<NominatimPlace>? searchSuggestions,
    bool? isSearching,
    bool? isLoading,
    String? Function()? errorMessage,
  }) {
    return MapState(
      userLocation: userLocation ?? this.userLocation,
      allGiveaways: allGiveaways ?? this.allGiveaways,
      filteredGiveaways: filteredGiveaways ?? this.filteredGiveaways,
      selectedGiveaway: selectedGiveaway != null ? selectedGiveaway() : this.selectedGiveaway,
      selectedRadiusKm: selectedRadiusKm != null ? selectedRadiusKm() : this.selectedRadiusKm,
      searchSuggestions: searchSuggestions ?? this.searchSuggestions,
      isSearching: isSearching ?? this.isSearching,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

class MapScreenController extends Notifier<MapState> {
  Timer? _searchDebounce;

  @override
  MapState build() {
    ref.onDispose(() {
      _searchDebounce?.cancel();
    });

    final defaultLocation = UserLocation.yogyakartaDefault;
    Future.microtask(() => initMap());

    return MapState(
      userLocation: defaultLocation,
      isLoading: true,
    );
  }

  Future<void> initMap() async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    final locationService = ref.read(locationServiceProvider);
    final discoverRepo = ref.read(discoverRepositoryProvider);

    // 1. Acquire current location (or default Yogyakarta)
    final loc = await locationService.getCurrentLocation(requestIfDenied: true);

    // 2. Load giveaways from repository
    try {
      final items = await discoverRepo.getGiveaways(
        userLat: loc.latitude,
        userLng: loc.longitude,
      );

      final withDistance = _computeDistances(items, loc.latitude, loc.longitude);

      state = state.copyWith(
        isLoading: false,
        userLocation: loc,
        allGiveaways: withDistance,
        filteredGiveaways: _applyRadiusFilter(withDistance, state.selectedRadiusKm),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        userLocation: loc,
        errorMessage: () => 'Gagal memuat undian pada peta: $e',
      );
    }
  }

  List<GiveawayModel> _computeDistances(
    List<GiveawayModel> list,
    double userLat,
    double userLng,
  ) {
    return list.map((g) {
      if (g.latitude != null && g.longitude != null) {
        final dist = LocationService.calculateDistanceKm(
          userLat,
          userLng,
          g.latitude!,
          g.longitude!,
        );
        return g.copyWith(distanceKm: dist);
      }
      return g;
    }).toList()
      ..sort((a, b) {
        if (a.distanceKm == null) return 1;
        if (b.distanceKm == null) return -1;
        return a.distanceKm!.compareTo(b.distanceKm!);
      });
  }

  List<GiveawayModel> _applyRadiusFilter(List<GiveawayModel> list, double? radiusKm) {
    if (radiusKm == null) return list;
    return list.where((g) {
      if (g.distanceKm == null) return false;
      return g.distanceKm! <= radiusKm;
    }).toList();
  }

  void setRadiusFilter(double? radiusKm) {
    state = state.copyWith(
      selectedRadiusKm: () => radiusKm,
      filteredGiveaways: _applyRadiusFilter(state.allGiveaways, radiusKm),
    );
  }

  void selectGiveaway(GiveawayModel? giveaway) {
    state = state.copyWith(selectedGiveaway: () => giveaway);
  }

  void onSearchQueryChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(searchSuggestions: [], isSearching: false);
      return;
    }

    state = state.copyWith(isSearching: true);
    // Debounce 600ms to respect Nominatim policy
    _searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      final nominatim = ref.read(nominatimServiceProvider);
      final results = await nominatim.searchLocation(trimmed);
      state = state.copyWith(
        searchSuggestions: results,
        isSearching: false,
      );
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    state = state.copyWith(searchSuggestions: [], isSearching: false);
  }

  void updateUserLocation(LatLng newLocation) {
    final updated = state.userLocation.copyWith(
      latitude: newLocation.latitude,
      longitude: newLocation.longitude,
      status: LocationPermissionStatus.granted,
      isFallback: false,
    );

    final withDistance = _computeDistances(
      state.allGiveaways,
      newLocation.latitude,
      newLocation.longitude,
    );

    state = state.copyWith(
      userLocation: updated,
      allGiveaways: withDistance,
      filteredGiveaways: _applyRadiusFilter(withDistance, state.selectedRadiusKm),
    );
  }

  Future<void> refreshLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final loc = await locationService.getCurrentLocation(requestIfDenied: true);
    final withDistance = _computeDistances(
      state.allGiveaways,
      loc.latitude,
      loc.longitude,
    );

    state = state.copyWith(
      userLocation: loc,
      allGiveaways: withDistance,
      filteredGiveaways: _applyRadiusFilter(withDistance, state.selectedRadiusKm),
    );
  }
}

final mapControllerProvider =
    NotifierProvider<MapScreenController, MapState>(MapScreenController.new);
