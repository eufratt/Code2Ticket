import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/supabase_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/home_remote_data_source.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/repositories/home_repository.dart';
import 'home_state.dart';

final homeRemoteDataSourceProvider = Provider<HomeRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return HomeRemoteDataSource(supabase);
});

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final remote = ref.watch(homeRemoteDataSourceProvider);
  final local = ref.watch(authLocalDataSourceProvider);
  final authRemote = ref.watch(authRemoteDataSourceProvider);
  return HomeRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
    authRemoteDataSource: authRemote,
  );
});

final homeControllerProvider =
    NotifierProvider<HomeController, HomeState>(HomeController.new);

class HomeController extends Notifier<HomeState> {
  late final HomeRepository _repository;

  @override
  HomeState build() {
    _repository = ref.watch(homeRepositoryProvider);
    Future.microtask(fetchSummary);
    return const HomeInitial();
  }

  Future<void> fetchSummary() async {
    state = const HomeLoading();
    try {
      final summary = await _repository.getHomeSummary();
      state = HomeLoaded(summary);
    } catch (e) {
      state = HomeError(e.toString());
    }
  }
}
