import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/supabase_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/ticket_remote_data_source.dart';
import '../../data/repositories/ticket_repository_impl.dart';
import '../../domain/models/ticket_model.dart';
import '../../domain/repositories/ticket_repository.dart';
import 'tickets_state.dart';

final ticketRemoteDataSourceProvider = Provider<TicketRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return TicketRemoteDataSource(supabase);
});

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  final remote = ref.watch(ticketRemoteDataSourceProvider);
  final local = ref.watch(authLocalDataSourceProvider);
  final authRemote = ref.watch(authRemoteDataSourceProvider);
  return TicketRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
    authRemoteDataSource: authRemote,
  );
});

final ticketsControllerProvider =
    NotifierProvider<TicketsController, TicketsState>(TicketsController.new);

class TicketsController extends Notifier<TicketsState> {
  late final TicketRepository _repository;

  @override
  TicketsState build() {
    _repository = ref.watch(ticketRepositoryProvider);
    // Auto load tickets when provider initializes
    Future.microtask(fetchTickets);
    return const TicketsInitial();
  }

  Future<void> fetchTickets() async {
    state = const TicketsLoading();
    try {
      final tickets = await _repository.getUserTickets();

      if (tickets.isEmpty) {
        state = const TicketsEmpty();
        return;
      }

      // Separate into active and history tickets
      final activeTickets = <TicketModel>[];
      final historyTickets = <TicketModel>[];

      for (final t in tickets) {
        if (t.status == 'waiting_for_draw' || t.status == 'eligible') {
          activeTickets.add(t);
        } else {
          historyTickets.add(t);
        }
      }

      final activeGroups = _groupByGiveaway(activeTickets);
      final historyGroups = _groupByGiveaway(historyTickets);

      state = TicketsLoaded(
        activeGroups: activeGroups,
        historyGroups: historyGroups,
        allTickets: tickets,
      );
    } catch (e) {
      state = TicketsError(e.toString());
    }
  }

  List<GiveawayTicketsGroup> _groupByGiveaway(List<TicketModel> list) {
    final Map<String, List<TicketModel>> map = {};
    for (final t in list) {
      map.putIfAbsent(t.giveawayId, () => []).add(t);
    }

    return map.values.map((ticketsInGroup) {
      final first = ticketsInGroup.first;
      return GiveawayTicketsGroup(
        giveawayId: first.giveawayId,
        giveawayTitle: first.giveawayTitle,
        giveawayCategory: first.giveawayCategory,
        prizeDescription: first.prizeDescription,
        prizeValueUsd: first.prizeValueUsd,
        drawAt: first.drawAt,
        tickets: ticketsInGroup,
      );
    }).toList();
  }
}
