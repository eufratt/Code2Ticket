import '../models/ticket_model.dart';

abstract class TicketRepository {
  /// Retrieves all tickets belonging to the currently logged in user.
  Future<List<TicketModel>> getUserTickets();

  /// Retrieves full detail of a specific ticket by its ID.
  Future<TicketModel?> getTicketDetail(String ticketId);
}
