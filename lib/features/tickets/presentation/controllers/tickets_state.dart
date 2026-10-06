import '../../domain/models/ticket_model.dart';

sealed class TicketsState {
  const TicketsState();
}

class TicketsInitial extends TicketsState {
  const TicketsInitial();
}

class TicketsLoading extends TicketsState {
  const TicketsLoading();
}

class TicketsLoaded extends TicketsState {
  final List<GiveawayTicketsGroup> activeGroups;
  final List<GiveawayTicketsGroup> historyGroups;
  final List<TicketModel> allTickets;

  const TicketsLoaded({
    required this.activeGroups,
    required this.historyGroups,
    required this.allTickets,
  });

  int get totalTicketsCount => allTickets.length;
  int get activeTicketsCount =>
      activeGroups.fold(0, (sum, g) => sum + g.ticketCount);
}

class TicketsEmpty extends TicketsState {
  const TicketsEmpty();
}

class TicketsError extends TicketsState {
  final String message;
  const TicketsError(this.message);
}
