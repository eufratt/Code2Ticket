import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/supabase_client.dart';
import '../../data/datasources/discover_remote_data_source.dart';
import '../../data/repositories/discover_repository_impl.dart';
import '../../domain/models/discover_filter_model.dart';
import '../../domain/repositories/discover_repository.dart';
import 'discover_state.dart';

final discoverRemoteDataSourceProvider = Provider<DiscoverRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return DiscoverRemoteDataSource(supabase);
});

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  final remote = ref.watch(discoverRemoteDataSourceProvider);
  return DiscoverRepositoryImpl(remote);
});

final discoverControllerProvider =
    NotifierProvider<DiscoverController, DiscoverState>(DiscoverController.new);

class DiscoverController extends Notifier<DiscoverState> {
  late final DiscoverRepository _repository;
  Timer? _debounceTimer;

  @override
  DiscoverState build() {
    _repository = ref.watch(discoverRepositoryProvider);
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    Future.microtask(fetchGiveaways);
    return const DiscoverState(isLoading: true);
  }

  Future<void> fetchGiveaways() async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final items = await _repository.getGiveaways(
        filter: state.filter,
        userLat: state.userLat,
        userLng: state.userLng,
      );
      state = state.copyWith(
        isLoading: false,
        giveaways: items,
        errorMessage: () => null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Gagal memuat undian: ${e.toString()}',
      );
    }
  }

  void onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      final updatedFilter = state.filter.copyWith(query: query);
      state = state.copyWith(filter: updatedFilter);
      fetchGiveaways();
    });
  }

  void setCategory(String category) {
    final updatedFilter = state.filter.copyWith(category: category);
    state = state.copyWith(filter: updatedFilter);
    fetchGiveaways();
  }

  void setSort(DiscoverSort sort) {
    final updatedFilter = state.filter.copyWith(sort: sort);
    state = state.copyWith(filter: updatedFilter);
    fetchGiveaways();
  }

  void applyFilter(DiscoverFilterModel newFilter) {
    state = state.copyWith(filter: newFilter);
    fetchGiveaways();
  }

  void resetFilter() {
    state = state.copyWith(
      filter: const DiscoverFilterModel(),
    );
    fetchGiveaways();
  }

  void setUserLocation(double lat, double lng) {
    state = state.copyWith(userLat: lat, userLng: lng);
    fetchGiveaways();
  }
}
