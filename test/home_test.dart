import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/features/home/domain/models/home_summary_model.dart';
import 'package:code2ticket/features/home/domain/repositories/home_repository.dart';
import 'package:code2ticket/features/home/presentation/controllers/home_controller.dart';
import 'package:code2ticket/features/home/presentation/controllers/home_state.dart';

class MockHomeRepository implements HomeRepository {
  final HomeSummaryModel summaryToReturn;

  MockHomeRepository({required this.summaryToReturn});

  @override
  Future<HomeSummaryModel> getHomeSummary({
    double? userLat,
    double? userLng,
  }) async {
    return summaryToReturn;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  group('Home Dashboard Tests', () {
    final now = DateTime.now();

    final sampleGiveaway = HomeGiveawayItem(
      id: 'gw-1',
      title: 'Jogja Tech Fest 2026',
      category: 'Tech',
      prize: 'MacBook Pro M3 Max',
      prizeValueUsd: 2499.0,
      locationName: 'Tugu Jogja',
      radiusKm: 15.0,
      drawAt: now.add(const Duration(days: 3)),
      isGeoRestricted: true,
    );

    final sampleSummary = HomeSummaryModel(
      totalTickets: 5,
      activeTickets: 4,
      nearestDraw: sampleGiveaway,
      recommendedDraws: [sampleGiveaway],
      nearbyDraws: [sampleGiveaway],
    );

    test('HomeSummaryModel correctly holds dashboard metrics', () {
      expect(sampleSummary.totalTickets, 5);
      expect(sampleSummary.activeTickets, 4);
      expect(sampleSummary.nearestDraw?.title, 'Jogja Tech Fest 2026');
      expect(sampleSummary.recommendedDraws.length, 1);
      expect(sampleSummary.nearbyDraws.first.isGeoRestricted, isTrue);
    });

    test('HomeController fetches and populates summary in HomeLoaded state', () async {
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(
            MockHomeRepository(summaryToReturn: sampleSummary),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(homeControllerProvider.notifier);
      await controller.fetchSummary();

      final state = container.read(homeControllerProvider);
      expect(state, isA<HomeLoaded>());

      final loaded = state as HomeLoaded;
      expect(loaded.summary.totalTickets, 5);
      expect(loaded.summary.activeTickets, 4);
      expect(loaded.summary.nearestDraw?.prizeValueUsd, 2499.0);
    });
  });
}
