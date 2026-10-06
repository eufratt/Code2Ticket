import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code2ticket/features/discover/domain/models/discover_filter_model.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/discover/domain/repositories/discover_repository.dart';
import 'package:code2ticket/features/discover/data/repositories/discover_repository_impl.dart';
import 'package:code2ticket/features/discover/data/datasources/discover_remote_data_source.dart';
import 'package:code2ticket/features/discover/presentation/controllers/discover_controller.dart';

class FakeDiscoverRemoteDataSource implements DiscoverRemoteDataSource {
  final List<GiveawayModel> items;
  FakeDiscoverRemoteDataSource(this.items);

  @override
  Future<List<GiveawayModel>> fetchGiveaways({double? userLat, double? userLng}) async {
    return items;
  }
}

class MockDiscoverRepository implements DiscoverRepository {
  final List<GiveawayModel> mockItems;

  MockDiscoverRepository(this.mockItems);

  @override
  Future<List<GiveawayModel>> getGiveaways({
    DiscoverFilterModel? filter,
    double? userLat,
    double? userLng,
  }) async {
    if (filter == null) return mockItems;
    var result = List<GiveawayModel>.from(mockItems);
    if (filter.query.isNotEmpty) {
      result = result
          .where((i) =>
              i.title.toLowerCase().contains(filter.query.toLowerCase()) ||
              i.prizeName.toLowerCase().contains(filter.query.toLowerCase()))
          .toList();
    }
    if (filter.category != 'Semua') {
      result = result.where((i) => i.category == filter.category).toList();
    }
    return result;
  }
}

void main() {
  final now = DateTime.now();
  final item1 = GiveawayModel(
    id: '1',
    title: 'MacBook Pro Tech Summit',
    category: 'Tech',
    prizeName: 'MacBook Pro M3',
    prizeValueUsd: 2000.0,
    startAt: now,
    endAt: now.add(const Duration(days: 10)),
    drawAt: now.add(const Duration(days: 12)),
    isGeoRestricted: true,
    distanceKm: 4.5,
  );
  final item2 = GiveawayModel(
    id: '2',
    title: 'PlayStation 5 Tournament',
    category: 'Gaming',
    prizeName: 'Sony PS5 Pro',
    prizeValueUsd: 800.0,
    startAt: now,
    endAt: now.add(const Duration(days: 5)),
    drawAt: now.add(const Duration(days: 6)),
    isGeoRestricted: false,
    distanceKm: 12.0,
  );
  final item3 = GiveawayModel(
    id: '3',
    title: 'Kuliner UGM Treats',
    category: 'Food',
    prizeName: 'Voucher 1 Tahun',
    prizeValueUsd: 300.0,
    startAt: now,
    endAt: now.add(const Duration(days: 20)),
    drawAt: now.add(const Duration(days: 22)),
    isGeoRestricted: false,
  );

  group('Discover Filter and Repository Tests', () {
    test('filters by query correctly', () async {
      final repo = MockDiscoverRepository([item1, item2, item3]);
      final filtered = await repo.getGiveaways(
        filter: const DiscoverFilterModel(query: 'ps5'),
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, '2');
    });

    test('filters by category correctly', () async {
      final repo = MockDiscoverRepository([item1, item2, item3]);
      final filtered = await repo.getGiveaways(
        filter: const DiscoverFilterModel(category: 'Tech'),
      );
      expect(filtered.length, 1);
      expect(filtered.first.title.contains('MacBook'), isTrue);
    });

    test('DiscoverRepositoryImpl sorts by deadline and prize correctly', () async {
      final fakeRemote = FakeDiscoverRemoteDataSource([item1, item2, item3]);
      final repo = DiscoverRepositoryImpl(fakeRemote);

      final sortedByPrize = await repo.getGiveaways(
        filter: const DiscoverFilterModel(sort: DiscoverSort.prizeDesc),
      );
      expect(sortedByPrize.first.prizeValueUsd, 2000.0);
      expect(sortedByPrize.last.prizeValueUsd, 300.0);

      final sortedByDeadline = await repo.getGiveaways(
        filter: const DiscoverFilterModel(sort: DiscoverSort.deadlineAsc),
      );
      expect(sortedByDeadline.first.id, '2');
      expect(sortedByDeadline.last.id, '3');
    });
  });

  group('DiscoverController Tests', () {
    test('initializes and loads items via mock repository', () async {
      final container = ProviderContainer(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(
            MockDiscoverRepository([item1, item2, item3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Trigger build and wait for microtask
      container.read(discoverControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(discoverControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.giveaways.length, 3);
    });

    test('updates category and filters giveaways', () async {
      final container = ProviderContainer(
        overrides: [
          discoverRepositoryProvider.overrideWithValue(
            MockDiscoverRepository([item1, item2, item3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(discoverControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      container.read(discoverControllerProvider.notifier).setCategory('Gaming');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(discoverControllerProvider);
      expect(state.filter.category, 'Gaming');
      expect(state.giveaways.length, 1);
      expect(state.giveaways.first.id, '2');
    });
  });
}
