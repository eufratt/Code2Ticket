import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/discover/domain/repositories/discover_repository.dart';
import 'package:code2ticket/features/discover/presentation/controllers/discover_controller.dart';
import 'package:code2ticket/features/map/presentation/controllers/map_controller.dart';

class MockDiscoverRepoForMap implements DiscoverRepository {
  final List<GiveawayModel> items;
  MockDiscoverRepoForMap(this.items);

  @override
  Future<List<GiveawayModel>> getGiveaways({
    dynamic filter,
    double? userLat,
    double? userLng,
  }) async {
    return items;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });
  final now = DateTime.now();
  final gNear = GiveawayModel(
    id: 'g-1',
    title: 'Near Giveaway',
    category: 'Tech',
    prizeName: 'Laptop',
    prizeValueUsd: 1000,
    latitude: -7.782884,
    longitude: 110.367069, // Tugu Jogja
    radiusKm: 5.0,
    isGeoRestricted: true,
    startAt: now,
    endAt: now.add(const Duration(days: 10)),
    drawAt: now.add(const Duration(days: 11)),
  );

  final gFar = GiveawayModel(
    id: 'g-2',
    title: 'Far Giveaway',
    category: 'Travel',
    prizeName: 'Voucher',
    prizeValueUsd: 500,
    latitude: -7.752020,
    longitude: 110.491467, // Prambanan (~14 km away)
    radiusKm: 20.0,
    isGeoRestricted: true,
    startAt: now,
    endAt: now.add(const Duration(days: 10)),
    drawAt: now.add(const Duration(days: 11)),
  );

  group('MapController Tests', () {
    test('initializes and computes distance from user location', () async {
      final container = ProviderContainer(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(
            MockDiscoverRepoForMap([gNear, gFar]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(mapControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(mapControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.allGiveaways.length, 2);
      expect(state.allGiveaways.first.distanceKm, isNotNull);
      // Closer one should be first
      expect(state.allGiveaways.first.id, 'g-1');
    });

    test('filters giveaways when radius is applied', () async {
      final container = ProviderContainer(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(
            MockDiscoverRepoForMap([gNear, gFar]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(mapControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Filter <= 5 km: only gNear should match
      container.read(mapControllerProvider.notifier).setRadiusFilter(5.0);

      final state = container.read(mapControllerProvider);
      expect(state.selectedRadiusKm, 5.0);
      expect(state.filteredGiveaways.length, 1);
      expect(state.filteredGiveaways.first.id, 'g-1');
    });

    test('selects and deselects giveaway correctly', () async {
      final container = ProviderContainer(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(
            MockDiscoverRepoForMap([gNear, gFar]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(mapControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      container.read(mapControllerProvider.notifier).selectGiveaway(gNear);
      expect(container.read(mapControllerProvider).selectedGiveaway?.id, 'g-1');

      container.read(mapControllerProvider.notifier).selectGiveaway(null);
      expect(container.read(mapControllerProvider).selectedGiveaway, isNull);
    });
  });
}
