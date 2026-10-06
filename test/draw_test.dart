import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';
import 'package:code2ticket/features/draw/domain/models/winner_model.dart';
import 'package:code2ticket/features/draw/domain/repositories/draw_repository.dart';
import 'package:code2ticket/features/draw/presentation/controllers/draw_controller.dart';
import 'package:code2ticket/features/draw/presentation/controllers/draw_detail_controller.dart';

class MockDrawRepository implements DrawRepository {
  final List<GiveawayModel> mockActive;
  final List<GiveawayModel> mockCompleted;
  final DrawDetailModel mockDetail;

  MockDrawRepository({
    required this.mockActive,
    required this.mockCompleted,
    required this.mockDetail,
  });

  @override
  Future<List<GiveawayModel>> getDraws({String status = 'active'}) async {
    if (status == 'active') return mockActive;
    if (status == 'completed') return mockCompleted;
    return [...mockActive, ...mockCompleted];
  }

  @override
  Future<DrawDetailModel> getDrawDetail(String giveawayId) async {
    return mockDetail;
  }
}

void main() {
  final now = DateTime.now();
  final sampleGiveaway = GiveawayModel(
    id: 'gw-101',
    title: 'Jogja Tech Fest 2026',
    category: 'Tech',
    prizeName: 'MacBook Pro M3 Max',
    prizeValueUsd: 2499.0,
    startAt: now.subtract(const Duration(days: 2)),
    endAt: now.add(const Duration(days: 28)),
    drawAt: now.add(const Duration(days: 30)),
    winnerCount: 1,
    status: 'active',
    ticketCount: 15,
  );

  final sampleWinner = WinnerModel(
    id: 'win-1',
    drawId: 'draw-1',
    ticketId: 'tkt-1',
    ticketNumber: '#TKT-TECH-00042',
    username: 'demouser',
    wonAt: now,
  );

  final sampleDetail = DrawDetailModel(
    giveaway: sampleGiveaway,
    drawId: 'draw-1',
    drawStatus: 'active',
    winners: [sampleWinner],
  );

  group('Draw Domain & Model Tests', () {
    test('WinnerModel parses from JSON correctly', () {
      final json = {
        'id': 'win-99',
        'draw_id': 'draw-88',
        'ticket_id': 'tkt-77',
        'tickets': {'ticket_number': '#TKT-999'},
        'users': {'username': 'champions'},
        'created_at': now.toIso8601String(),
      };
      final winner = WinnerModel.fromJson(json);
      expect(winner.ticketNumber, '#TKT-999');
      expect(winner.username, 'champions');
    });

    test('DrawDetailModel accurately detects onchain verification and drawn status', () {
      final pendingDetail = DrawDetailModel(
        giveaway: sampleGiveaway,
        drawStatus: 'active',
      );
      expect(pendingDetail.isDrawn, isFalse);
      expect(pendingDetail.isVerifiedOnchain, isFalse);

      final completedDetail = DrawDetailModel(
        giveaway: sampleGiveaway,
        drawStatus: 'verified_onchain',
        txHash: '0x123456789abcdef',
      );
      expect(completedDetail.isDrawn, isTrue);
      expect(completedDetail.isVerifiedOnchain, isTrue);
    });
  });

  group('Draw Controllers Tests', () {
    test('DrawListController fetches and populates active and completed draws', () async {
      final container = ProviderContainer(
        overrides: [
          drawRepositoryProvider.overrideWithValue(
            MockDrawRepository(
              mockActive: [sampleGiveaway],
              mockCompleted: [],
              mockDetail: sampleDetail,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(drawListControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(drawListControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.activeDraws.length, 1);
      expect(state.activeDraws.first.id, 'gw-101');
    });

    test('drawDetailProvider loads DrawDetailModel for giveawayId', () async {
      final container = ProviderContainer(
        overrides: [
          drawRepositoryProvider.overrideWithValue(
            MockDrawRepository(
              mockActive: [sampleGiveaway],
              mockCompleted: [],
              mockDetail: sampleDetail,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final detail = await container.read(drawDetailProvider('gw-101').future);
      expect(detail.giveaway.id, 'gw-101');
      expect(detail.winners.first.ticketNumber, '#TKT-TECH-00042');
    });
  });
}
