import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code2ticket/core/database/supabase_client.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/data/datasources/draw_remote_data_source.dart';
import 'package:code2ticket/features/draw/data/repositories/draw_repository_impl.dart';
import 'package:code2ticket/features/draw/domain/repositories/draw_repository.dart';

final drawRemoteDataSourceProvider = Provider<DrawRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return DrawRemoteDataSource(supabase);
});

final drawRepositoryProvider = Provider<DrawRepository>((ref) {
  final remote = ref.watch(drawRemoteDataSourceProvider);
  return DrawRepositoryImpl(remote);
});

class DrawListState {
  final bool isLoading;
  final List<GiveawayModel> activeDraws;
  final List<GiveawayModel> completedDraws;
  final String? errorMessage;

  const DrawListState({
    this.isLoading = false,
    this.activeDraws = const [],
    this.completedDraws = const [],
    this.errorMessage,
  });

  DrawListState copyWith({
    bool? isLoading,
    List<GiveawayModel>? activeDraws,
    List<GiveawayModel>? completedDraws,
    String? Function()? errorMessage,
  }) {
    return DrawListState(
      isLoading: isLoading ?? this.isLoading,
      activeDraws: activeDraws ?? this.activeDraws,
      completedDraws: completedDraws ?? this.completedDraws,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

class DrawListController extends Notifier<DrawListState> {
  late final DrawRepository _repository;

  @override
  DrawListState build() {
    _repository = ref.watch(drawRepositoryProvider);
    Future.microtask(fetchDraws);
    return const DrawListState(isLoading: true);
  }

  Future<void> fetchDraws() async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final active = await _repository.getDraws(status: 'active');
      final completed = await _repository.getDraws(status: 'completed');

      state = state.copyWith(
        isLoading: false,
        activeDraws: active,
        completedDraws: completed,
        errorMessage: () => null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Gagal memuat undian: ${e.toString()}',
      );
    }
  }
}

final drawListControllerProvider =
    NotifierProvider<DrawListController, DrawListState>(DrawListController.new);
