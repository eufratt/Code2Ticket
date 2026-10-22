import 'package:code2ticket/core/db/cache_store.dart';
import 'package:code2ticket/features/draw/draw_models.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';

/// CacheStore di memori untuk tes widget/controller (tanpa SQLite).
class MemoryCacheStore implements CacheStore {
  final Map<String, Giveaway> giveaways = {};
  DateTime? giveawaysAt;
  final Map<String, List<Ticket>> tickets = {};
  final Map<String, DateTime> ticketsAt = {};
  final Map<String, List<String>> searches = {};
  final Map<String, Map<String, CachedDrawResult>> draws = {};
  bool failing = false; // simulasi cache rusak: semua operasi melempar

  void _check() {
    if (failing) throw StateError('cache rusak');
  }

  @override
  Future<void> saveGiveaways(List<Giveaway> items) async {
    _check();
    for (final g in items) {
      giveaways[g.id] = g;
    }
    giveawaysAt = DateTime.now();
  }

  @override
  Future<List<Giveaway>> loadGiveaways() async {
    _check();
    return giveaways.values.toList();
  }

  @override
  Future<Giveaway?> loadGiveaway(String id) async {
    _check();
    return giveaways[id];
  }

  @override
  Future<DateTime?> giveawaysUpdatedAt() async => giveawaysAt;

  @override
  Future<void> replaceTickets(String userId, List<Ticket> items) async {
    _check();
    tickets[userId] = List.of(items);
    ticketsAt[userId] = DateTime.now();
  }

  @override
  Future<List<Ticket>> loadTickets(String userId) async {
    _check();
    return tickets[userId] ?? [];
  }

  @override
  Future<DateTime?> ticketsUpdatedAt(String userId) async => ticketsAt[userId];

  @override
  Future<void> saveDrawResult(String userId, CachedDrawResult r) async {
    _check();
    draws.putIfAbsent(userId, () => {})[r.giveawayId] = CachedDrawResult(
        giveawayId: r.giveawayId, winners: r.winners, drawnAtMs: r.drawnAtMs, totalTickets: r.totalTickets, cachedAt: DateTime.now());
  }

  @override
  Future<CachedDrawResult?> loadDrawResult(String userId, String giveawayId) async {
    _check();
    return draws[userId]?[giveawayId];
  }

  @override
  Future<List<String>> recentSearches(String userId, {int limit = 10}) async =>
      (searches[userId] ?? []).take(limit).toList();

  @override
  Future<void> addSearch(String userId, String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final l = searches[userId] ??= [];
    l.remove(q);
    l.insert(0, q);
    if (l.length > 10) l.removeRange(10, l.length);
  }

  @override
  Future<void> deleteSearch(String userId, String query) async => searches[userId]?.remove(query);

  @override
  Future<void> clearSearches(String userId) async => searches.remove(userId);

  @override
  Future<void> clearUserData({String? userId}) async {
    giveaways.clear();
    giveawaysAt = null;
    tickets.clear();
    ticketsAt.clear();
    draws.clear();
    if (userId != null) {
      searches.remove(userId);
    } else {
      searches.clear();
    }
  }
}
