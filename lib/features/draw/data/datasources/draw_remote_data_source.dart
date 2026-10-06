import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:code2ticket/features/discover/data/datasources/discover_remote_data_source.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';
import 'package:code2ticket/features/draw/domain/models/winner_model.dart';

class DrawRemoteDataSource {
  final SupabaseClient _supabase;

  const DrawRemoteDataSource(this._supabase);

  Future<List<GiveawayModel>> fetchDraws({String status = 'active'}) async {
    try {
      var query = _supabase
          .from('giveaways')
          .select('*, tickets(count)');

      if (status.isNotEmpty && status != 'all') {
        query = query.eq('status', status);
      }

      final res = await query.order('draw_at', ascending: true);
      final list = res as List<dynamic>;
      return list
          .map((item) => GiveawayModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching draws from Supabase: $e');
      final fallback = DiscoverRemoteDataSource(_supabase);
      final all = await fallback.fetchGiveaways();
      if (status == 'all') return all;
      return all.where((g) => g.status == status).toList();
    }
  }

  Future<DrawDetailModel> fetchDrawDetail(String giveawayId) async {
    GiveawayModel? giveaway;

    try {
      final gRes = await _supabase
          .from('giveaways')
          .select('*, tickets(count)')
          .eq('id', giveawayId)
          .maybeSingle();

      if (gRes != null) {
        giveaway = GiveawayModel.fromJson(gRes);
      }
    } catch (e) {
      debugPrint('Error fetching giveaway detail: $e');
    }

    // Fallback if not found in db or offline
    if (giveaway == null) {
      final fallback = DiscoverRemoteDataSource(_supabase);
      final all = await fallback.fetchGiveaways();
      giveaway = all.firstWhere(
        (g) => g.id == giveawayId,
        orElse: () => all.first,
      );
    }

    // Fetch draw record if exists
    String? drawId;
    String? drawStatus;
    DateTime? drawnAt;
    String? seedCommitment;
    String? txHash;
    List<WinnerModel> winners = [];

    try {
      final drawRes = await _supabase
          .from('draws')
          .select()
          .eq('giveaway_id', giveawayId)
          .order('drawn_at', ascending: false)
          .maybeSingle();

      if (drawRes != null) {
        drawId = drawRes['id'] as String?;
        drawStatus = drawRes['status'] as String?;
        drawnAt = drawRes['drawn_at'] != null
            ? DateTime.tryParse(drawRes['drawn_at'].toString())
            : null;
        seedCommitment = drawRes['seed_commitment'] as String?;
        txHash = drawRes['tx_hash'] as String?;

        if (drawId != null) {
          final winnersRes = await _supabase
              .from('winners')
              .select('id, draw_id, ticket_id, user_id, created_at, tickets(ticket_number), users(username)')
              .eq('draw_id', drawId);

          final wList = winnersRes as List<dynamic>;
          winners = wList
              .map((w) => WinnerModel.fromJson(w as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching draw proof & winners: $e');
    }

    return DrawDetailModel(
      giveaway: giveaway,
      drawId: drawId,
      drawStatus: drawStatus ?? giveaway.status,
      drawnAt: drawnAt,
      seedCommitment: seedCommitment,
      txHash: txHash,
      winners: winners,
    );
  }
}
