import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/location/location_service.dart';
import '../../widgets/state_views.dart';
import '../giveaways/giveaway_card.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'discover_controller.dart';
import 'discover_filters.dart';
import 'manual_location_dialog.dart';

/// S-DISC: pencarian (debounce 400 ms), filter, urutan, dan riwayat pencarian.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final c = context.read<DiscoverController>();
    _text.text = c.filters.query;
    _focus.addListener(() => setState(() {}));
    Future.microtask(c.ensureLoaded);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _useHistory(DiscoverController c, String q) {
    _text.text = q;
    _text.selection = TextSelection.collapsed(offset: q.length);
    _focus.unfocus();
    c.submitQuery(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DiscoverController>();
    final showHistory = _focus.hasFocus && _text.text.trim().isEmpty && c.history.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            key: const Key('open_map'),
            tooltip: 'Peta',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/map'),
          ),
          IconButton(
            key: const Key('open_filter'),
            tooltip: 'Filter',
            icon: Badge(
              isLabelVisible: c.filters.activeFilterCount > 0,
              label: Text('${c.filters.activeFilterCount}'),
              child: const Icon(Icons.tune),
            ),
            onPressed: () => _openFilters(context, c),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const Key('search_field'),
              controller: _text,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari giveaway, hadiah, atau penyelenggara',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _text.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _text.clear();
                          c.submitQuery('');
                          setState(() {});
                        },
                      ),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (v) {
                c.onQueryChanged(v);
                setState(() {});
              },
              onSubmitted: (v) {
                _focus.unfocus();
                c.submitQuery(v);
              },
            ),
          ),
          _SortBar(controller: c),
          if (c.locationProblem != null) _LocationBanner(controller: c),
          if (c.offline) OfflineBanner(cachedAt: c.cachedAt),
          Expanded(child: showHistory ? _History(controller: c, onPick: (q) => _useHistory(c, q)) : _Results(controller: c)),
        ],
      ),
    );
  }

  Future<void> _openFilters(BuildContext context, DiscoverController c) async {
    final result = await showModalBottomSheet<DiscoverFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(initial: c.filters),
    );
    if (result != null) await c.setFilters(result);
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.controller});
  final DiscoverController controller;

  @override
  Widget build(BuildContext context) {
    final f = controller.filters;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            key: const Key('nearby_chip'),
            avatar: controller.locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.near_me, size: 18),
            label: const Text('Terdekat'),
            selected: f.nearby,
            onSelected: controller.locating ? null : (on) => on ? controller.enableNearby() : controller.disableNearby(),
          ),
          if (f.nearby)
            for (final km in const [5, 10, 25]) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                key: Key('radius_$km'),
                label: Text('$km km'),
                selected: f.nearbyRadiusKm == km,
                onSelected: (_) => controller.setNearbyRadius(km),
              ),
            ],
          if (controller.manualLabel != null) ...[
            const SizedBox(width: 8),
            InputChip(
              key: const Key('manual_chip'),
              avatar: const Icon(Icons.place, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(controller.manualLabel!, overflow: TextOverflow.ellipsis),
              ),
              onDeleted: controller.disableNearby,
            ),
          ],
          const SizedBox(width: 8),
          PopupMenuButton<GiveawaySort>(
            key: const Key('sort_menu'),
            tooltip: 'Urutkan',
            initialValue: f.sort,
            onSelected: (s) => controller.setFilters(f.copyWith(sort: s)),
            itemBuilder: (_) => [
              for (final s in GiveawaySort.values)
                if (s != GiveawaySort.nearest || controller.position != null)
                  PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: Chip(
              avatar: const Icon(Icons.sort, size: 18),
              label: Text(f.sort.label),
            ),
          ),
          if (f.category != null) ...[
            const SizedBox(width: 8),
            InputChip(
              label: Text(categoryLabel(f.category!)),
              onDeleted: () => controller.setFilters(f.copyWith(category: null)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Alasan Terdekat tidak bisa dipakai (izin ditolak, ditolak permanen, layanan mati, posisi tak tersedia)
/// beserta jalan keluarnya: izinkan/buka pengaturan, atau cari tempat secara manual.
class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.controller});
  final DiscoverController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.locationProblem!;
    final scheme = Theme.of(context).colorScheme;
    final opensSettings = status == LocationStatus.deniedForever || status == LocationStatus.serviceOff;
    return Container(
      key: const Key('location_banner'),
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locationStatusMessage(status), style: TextStyle(color: scheme.onErrorContainer)),
          Wrap(spacing: 8, children: [
            TextButton(
              key: const Key('location_action'),
              onPressed: opensSettings ? controller.openLocationSettings : controller.enableNearby,
              child: Text(locationActionLabel(status)),
            ),
            TextButton(
              key: const Key('manual_location'),
              onPressed: () async {
                final place = await showManualLocationDialog(context);
                if (place != null) await controller.useManualPlace(place);
              },
              child: const Text('Cari tempat'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.controller, required this.onPick});
  final DiscoverController controller;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('Riwayat pencarian', style: Theme.of(context).textTheme.titleSmall)),
              TextButton(
                key: const Key('clear_history'),
                onPressed: controller.clearHistory,
                child: const Text('Hapus semua'),
              ),
            ],
          ),
        ),
        for (final q in controller.history)
          ListTile(
            key: Key('history_$q'),
            leading: const Icon(Icons.history),
            title: Text(q),
            onTap: () => onPick(q),
            trailing: IconButton(
              tooltip: 'Hapus dari riwayat',
              icon: const Icon(Icons.close),
              onPressed: () => controller.deleteHistory(q),
            ),
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.controller});
  final DiscoverController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    switch (c.state) {
      case LoadState.idle:
      case LoadState.loading:
        if (c.items.isEmpty) return const LoadingView();
      case LoadState.error:
        if (c.items.isEmpty) return ErrorRetryView(message: c.error ?? 'Gagal memuat.', onRetry: c.search);
      case LoadState.loaded:
        break;
    }
    return RefreshIndicator(
      onRefresh: c.search,
      child: c.items.isEmpty
          ? ListView(children: [
              SizedBox(
                height: 360,
                child: EmptyView(
                  icon: Icons.search_off,
                  message: c.filters.query.trim().isEmpty && c.filters.activeFilterCount == 0
                      ? 'Belum ada giveaway.\nTarik ke bawah untuk memuat ulang.'
                      : 'Tidak ada giveaway yang cocok.\nCoba kata kunci atau filter lain.',
                ),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 140),
              itemCount: c.items.length + (c.hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == c.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: c.loadingMore
                          ? const CircularProgressIndicator()
                          : TextButton(key: const Key('load_more'), onPressed: c.loadMore, child: const Text('Muat lebih banyak')),
                    ),
                  );
                }
                final g = c.items[i];
                return GiveawayCard(
                  giveaway: g,
                  onTap: () {
                    c.commitQuery();
                    context.push('/giveaway/${g.id}', extra: g);
                  },
                );
              },
            ),
    );
  }
}

/// Bottom sheet filter: kategori, rentang nilai hadiah (USD), deadline, dan status.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});
  final DiscoverFilters initial;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late DiscoverFilters _f = widget.initial;
  late final _min = TextEditingController(text: _fmt(widget.initial.minValue));
  late final _max = TextEditingController(text: _fmt(widget.initial.maxValue));
  String? _error;

  static String _fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));

  void _apply() {
    final lo = _parse(_min.text), hi = _parse(_max.text);
    if ((_min.text.trim().isNotEmpty && lo == null) || (_max.text.trim().isNotEmpty && hi == null) ||
        (lo != null && lo < 0) || (hi != null && hi < 0)) {
      setState(() => _error = 'Nilai hadiah harus berupa angka positif.');
      return;
    }
    if (lo != null && hi != null && lo > hi) {
      setState(() => _error = 'Nilai minimum tidak boleh lebih besar dari maksimum.');
      return;
    }
    Navigator.pop(context, _f.copyWith(minValue: lo, maxValue: hi));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String t, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter', style: theme.textTheme.titleLarge),
            section(
              'Kategori',
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                  label: const Text('Semua'),
                  selected: _f.category == null,
                  onSelected: (_) => setState(() => _f = _f.copyWith(category: null)),
                ),
                for (final c in giveawayCategories)
                  ChoiceChip(
                    key: Key('cat_$c'),
                    label: Text(categoryLabel(c)),
                    selected: _f.category == c,
                    onSelected: (_) => setState(() => _f = _f.copyWith(category: c)),
                  ),
              ]),
            ),
            section(
              'Nilai hadiah (USD)',
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('min_value'),
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Minimum'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('max_value'),
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Maksimum'),
                  ),
                ),
              ]),
            ),
            section(
              'Deadline',
              Wrap(spacing: 8, children: [
                for (final (label, days) in const [('Semua', null), ('Hari ini', 1), ('7 hari', 7), ('30 hari', 30)])
                  ChoiceChip(
                    label: Text(label),
                    selected: _f.deadlineDays == days,
                    onSelected: (_) => setState(() => _f = _f.copyWith(deadlineDays: days)),
                  ),
              ]),
            ),
            section(
              'Status',
              Wrap(spacing: 8, children: [
                for (final s in GiveawayStatusFilter.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _f.status == s,
                    onSelected: (_) => setState(() => _f = _f.copyWith(status: s)),
                  ),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              TextButton(
                key: const Key('reset_filter'),
                onPressed: () => Navigator.pop(
                  context,
                  widget.initial.copyWith(
                    category: null, minValue: null, maxValue: null, deadlineDays: null,
                    status: GiveawayStatusFilter.active,
                  ),
                ),
                child: const Text('Atur ulang'),
              ),
              const Spacer(),
              FilledButton(key: const Key('apply_filter'), onPressed: _apply, child: const Text('Terapkan')),
            ]),
          ],
        ),
      ),
    );
  }
}
