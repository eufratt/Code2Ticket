import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/ticket_model.dart';

class TicketRemoteDataSource {
  final SupabaseClient _supabase;

  const TicketRemoteDataSource(this._supabase);

  /// Fetches all tickets belonging to a specific user.
  Future<List<TicketModel>> fetchUserTickets(String userId) async {
    try {
      final response = await _supabase
          .from('tickets')
          .select('''
            id,
            ticket_number,
            status,
            created_at,
            giveaway_id,
            giveaways (
              id,
              title,
              category,
              prize_name,
              description,
              prize_value_usd,
              draw_at,
              status
            ),
            codes (
              code
            ),
            winners (
              id
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final list = response as List<dynamic>;
      return list
          .map((item) => TicketModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Gagal memuat daftar tiket: $e');
    }
  }

  /// Fetches single ticket detail with its associated giveaway and code info.
  Future<TicketModel?> fetchTicketDetail(String ticketId) async {
    try {
      final response = await _supabase
          .from('tickets')
          .select('''
            id,
            ticket_number,
            status,
            created_at,
            giveaway_id,
            giveaways (
              id,
              title,
              category,
              prize_name,
              description,
              prize_value_usd,
              draw_at,
              status
            ),
            codes (
              code
            ),
            winners (
              id
            )
          ''')
          .eq('id', ticketId)
          .maybeSingle();

      if (response == null) return null;
      return TicketModel.fromJson(response);
    } catch (e) {
      throw Exception('Gagal memuat detail tiket: $e');
    }
  }
}
