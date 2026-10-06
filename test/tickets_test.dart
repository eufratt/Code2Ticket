import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/features/tickets/domain/models/ticket_model.dart';
import 'package:code2ticket/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:code2ticket/features/tickets/presentation/controllers/tickets_controller.dart';
import 'package:code2ticket/features/tickets/presentation/controllers/tickets_state.dart';

class MockTicketRepository implements TicketRepository {
  final List<TicketModel> ticketsToReturn;

  MockTicketRepository({required this.ticketsToReturn});

  @override
  Future<List<TicketModel>> getUserTickets() async {
    return ticketsToReturn;
  }

  @override
  Future<TicketModel?> getTicketDetail(String ticketId) async {
    return ticketsToReturn.where((t) => t.id == ticketId).firstOrNull;
  }
}

void main() {
  group('TicketModel & Grouping Tests', () {
    final now = DateTime.now();

    final ticketActive1 = TicketModel(
      id: 't-1',
      ticketNumber: 'TKT-GAM-00001',
      giveawayId: 'gw-1',
      giveawayTitle: 'PlayStation 5 Pro',
      giveawayCategory: 'Gaming',
      prizeDescription: 'PS5 Pro Bundle',
      prizeValueUsd: 899.0,
      status: 'waiting_for_draw',
      createdAt: now,
      drawAt: now.add(const Duration(days: 10)),
    );

    final ticketActive2 = TicketModel(
      id: 't-2',
      ticketNumber: 'TKT-GAM-00002',
      giveawayId: 'gw-1',
      giveawayTitle: 'PlayStation 5 Pro',
      giveawayCategory: 'Gaming',
      prizeDescription: 'PS5 Pro Bundle',
      prizeValueUsd: 899.0,
      status: 'eligible',
      createdAt: now,
      drawAt: now.add(const Duration(days: 10)),
    );

    final ticketWinner = TicketModel(
      id: 't-3',
      ticketNumber: 'TKT-TEC-00001',
      giveawayId: 'gw-2',
      giveawayTitle: 'MacBook Pro M3 Max',
      giveawayCategory: 'Tech',
      prizeDescription: 'MacBook Pro 16',
      prizeValueUsd: 2499.0,
      status: 'winner',
      isWinner: true,
      createdAt: now,
      drawAt: now.subtract(const Duration(days: 1)),
    );

    test('GiveawayTicketsGroup calculates properties correctly', () {
      final group = GiveawayTicketsGroup(
        giveawayId: 'gw-1',
        giveawayTitle: 'PlayStation 5 Pro',
        giveawayCategory: 'Gaming',
        prizeDescription: 'PS5 Pro Bundle',
        prizeValueUsd: 899.0,
        tickets: [ticketActive1, ticketActive2],
      );

      expect(group.ticketCount, 2);
      expect(group.hasWinner, isFalse);
    });

    test('TicketsController groups tickets and splits active vs history', () async {
      final container = ProviderContainer(
        overrides: [
          ticketRepositoryProvider.overrideWithValue(
            MockTicketRepository(
              ticketsToReturn: [ticketActive1, ticketActive2, ticketWinner],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(ticketsControllerProvider.notifier);
      await controller.fetchTickets();

      final state = container.read(ticketsControllerProvider);
      expect(state, isA<TicketsLoaded>());

      final loaded = state as TicketsLoaded;
      expect(loaded.totalTicketsCount, 3);
      expect(loaded.activeTicketsCount, 2);
      expect(loaded.activeGroups.length, 1);
      expect(loaded.activeGroups.first.giveawayTitle, 'PlayStation 5 Pro');
      expect(loaded.historyGroups.length, 1);
      expect(loaded.historyGroups.first.hasWinner, isTrue);
    });

    test('TicketsController handles empty ticket state', () async {
      final container = ProviderContainer(
        overrides: [
          ticketRepositoryProvider.overrideWithValue(
            MockTicketRepository(ticketsToReturn: []),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(ticketsControllerProvider.notifier);
      await controller.fetchTickets();

      final state = container.read(ticketsControllerProvider);
      expect(state, isA<TicketsEmpty>());
    });
  });
}
