import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/rates_controller.dart';
import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/rupiah_input.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
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
            padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s4),
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
          _ActiveSummary(controller: c),
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
      builder: (_) => FilterSheet(initial: c.filters, locationKnown: c.position != null, onUseLocation: c.enableNearby),
    );
    if (result != null) await c.setFilters(result);
  }
}

/// Pilihan deadline di sheet filter dan baris ringkas (hari; null = semua).
const _deadlineOptions = [('Semua', null), ('Hari ini', 1), ('7 hari', 7), ('30 hari', 30)];

/// Urutan tampil pilihan "Urutkan" di sheet filter.
const _sortOrder = [GiveawaySort.deadline, GiveawaySort.nearest, GiveawaySort.value, GiveawaySort.newest];

/// Baris ringkas di bawah kolom cari: HANYA filter/urutan yang bukan bawaan, masing-masing chip dengan tombol hapus
/// (langsung memperbarui daftar). Semua bawaan = tidak tampil. Lokasi manual dan radius Terdekat ikut di sini karena
/// ikut menyaring daftar.
class _ActiveSummary extends StatelessWidget {
  const _ActiveSummary({required this.controller});
  final DiscoverController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = c.filters;
    Widget chip(Key key, String label, VoidCallback onDeleted, String tooltip) => Padding(
          padding: const EdgeInsets.only(right: Spacing.s8),
          child: InputChip(key: key, label: Text(label), deleteButtonTooltipMessage: tooltip, onDeleted: onDeleted),
        );
    String? valueLabel() {
      final lo = f.minValueIdr, hi = f.maxValueIdr;
      if (lo == null && hi == null) return null;
      if (lo != null && hi != null) return 'Nilai: ${context.money(lo)} - ${context.money(hi)}';
      return lo != null ? 'Nilai: min. ${context.money(lo)}' : 'Nilai: maks. ${context.money(hi)}';
    }

    final value = valueLabel();
    final chips = <Widget>[
      if (c.locating)
        const Padding(
          padding: EdgeInsets.only(right: Spacing.s12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: Spacing.s8),
            Text('Mencari lokasi...'),
          ]),
        ),
      if (f.status != null) chip(const Key('summary_status'), f.status!.label, () => c.setFilters(f.copyWith(status: null)), 'Hapus filter status'),
      if (f.sort != GiveawaySort.deadline)
        chip(const Key('summary_sort'), 'Urut: ${f.sort.label}', () => c.setFilters(f.copyWith(sort: GiveawaySort.deadline)), 'Hapus urutan'),
      if (f.category != null)
        chip(const Key('summary_category'), categoryLabel(f.category!), () => c.setFilters(f.copyWith(category: null)), 'Hapus filter kategori'),
      if (f.deadlineDays != null)
        chip(
          const Key('summary_deadline'),
          'Deadline: ${_deadlineOptions.firstWhere((o) => o.$2 == f.deadlineDays, orElse: () => ('${f.deadlineDays} hari', null)).$1}',
          () => c.setFilters(f.copyWith(deadlineDays: null)),
          'Hapus filter deadline',
        ),
      if (value != null) chip(const Key('summary_value'), value, () => c.setFilters(f.copyWith(minValueIdr: null, maxValueIdr: null)), 'Hapus filter nilai hadiah'),
      if (f.nearby) chip(const Key('summary_radius'), 'Radius ${f.nearbyRadiusKm} km', c.disableNearby, 'Matikan Terdekat'),
      if (c.manualLabel != null)
        Padding(
          padding: const EdgeInsets.only(right: Spacing.s8),
          child: InputChip(
            key: const Key('manual_chip'),
            deleteButtonTooltipMessage: 'Hapus lokasi manual',
            avatar: const Icon(Icons.place, size: 18),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(c.manualLabel!, overflow: TextOverflow.ellipsis),
            ),
            onDeleted: c.disableNearby,
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      key: const Key('filter_summary'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.screen, vertical: Spacing.s4),
      child: Row(children: chips),
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
    final sc = context.colors.statusWarning;
    final opensSettings = status == LocationStatus.deniedForever || status == LocationStatus.serviceOff;
    return Container(
      key: const Key('location_banner'),
      width: double.infinity,
      color: sc.bg,
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locationStatusMessage(status), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: sc.fg)),
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
      padding: const EdgeInsets.only(bottom: Spacing.s16),
      children: [
        SectionHeader(
          'Riwayat pencarian',
          padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.s8, 0),
          actionLabel: 'Hapus semua',
          actionKey: const Key('clear_history'),
          onAction: controller.clearHistory,
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
        if (c.items.isEmpty) return const SkeletonLoader(count: 3);
      case LoadState.error:
        if (c.items.isEmpty) return ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.search);
      case LoadState.loaded:
        break;
    }
    return RefreshIndicator(
      onRefresh: c.search,
      child: c.items.isEmpty
          ? ListView(children: [
              SizedBox(
                height: 360,
                child: c.filters.query.trim().isEmpty && c.filters.activeFilterCount == 0
                    ? const EmptyState(
                        icon: Icons.search_off,
                        title: 'Belum ada giveaway',
                        message: 'Tarik ke bawah untuk memuat ulang.',
                      )
                    : EmptyState(
                        icon: Icons.search_off,
                        title: 'Tidak ada giveaway yang cocok',
                        message: c.filters.status == null
                            ? 'Coba kata kunci atau filter lain.'
                            : 'Coba kata kunci atau filter lain.\nCoba pilih status lain.',
                      ),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s16),
              itemCount: c.items.length + (c.hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == c.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(Spacing.s12),
                    child: Center(
                      child: c.loadingMore
                          ? const CircularProgressIndicator()
                          : TextButton(key: const Key('load_more'), onPressed: c.loadMore, child: const Text('Muat lebih banyak')),
                    ),
                  );
                }
                final g = c.items[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.s4 + 2),
                  child: GiveawayCard(
                    giveaway: g,
                    onTap: () {
                      c.commitQuery();
                      context.push('/giveaway/${g.id}', extra: g);
                    },
                  ),
                );
              },
            ),
    );
  }
}

/// Satu-satunya tempat status dan urutan: Status, Urutkan, lalu kategori, deadline, rentang nilai hadiah (mata uang
/// tampilan, dikonversi ke rupiah saat diterapkan), dan radius bila mode Terdekat aktif. "Terdekat" butuh lokasi:
/// tanpa [locationKnown] nonaktif ("Butuh lokasi"), dan [onUseLocation] (alur izin lokasi yang sudah ada) ditawarkan.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, this.locationKnown = false, this.onUseLocation});
  final DiscoverFilters initial;
  final bool locationKnown;
  final Future<void> Function()? onUseLocation;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late DiscoverFilters _f = widget.initial;
  late final _min = TextEditingController(text: _fmt(widget.initial.minValueIdr));
  late final _max = TextEditingController(text: _fmt(widget.initial.maxValueIdr));
  String? _error;

  /// Mata uang isian = mata uang tampilan pengguna; tanpa kurs (offline) rupiah.
  String get _code => prizeCurrency(context.read<SettingsController>().currency, context.read<RatesController>().rates);

  /// IDR dan JPY bilangan bulat; USD dan EUR dua desimal.
  int get _decimals => _code == 'IDR' || _code == 'JPY' ? 0 : 2;

  String _fmt(int? idr) => idr == null ? '' : prizeInputText(idr, _code, context.read<RatesController>().rates);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  double? _parse(String s) => s.trim().isEmpty ? null : parseIdNumber(s);

  void _apply() {
    final lo = _parse(_min.text), hi = _parse(_max.text);
    if ((_min.text.trim().isNotEmpty && lo == null) || (_max.text.trim().isNotEmpty && hi == null)) {
      setState(() => _error = 'Nilai hadiah harus berupa angka positif.');
      return;
    }
    if (lo != null && hi != null && lo > hi) {
      setState(() => _error = 'Nilai minimum tidak boleh lebih besar dari maksimum.');
      return;
    }
    // Minimum dibulatkan ke bawah dan maksimum ke atas supaya hasil di tepi rentang tidak hilang.
    final rates = context.read<RatesController>().rates;
    Navigator.pop(
      context,
      _f.copyWith(
        minValueIdr: lo == null ? null : prizeToIdr(lo, _code, rates, up: false),
        maxValueIdr: hi == null ? null : prizeToIdr(hi, _code, rates, up: true),
      ),
    );
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
      padding: EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, MediaQuery.of(context).viewInsets.bottom + Spacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('Filter', style: theme.textTheme.titleLarge),
                section(
                  'Status',
                  Wrap(spacing: 8, children: [
                    for (final s in <GiveawayStatusFilter?>[null, ...GiveawayStatusFilter.values])
                      ChoiceChip(
                        key: Key('sheet_status_${s?.name ?? 'all'}'),
                        label: Text(s?.label ?? 'Semua'),
                        showCheckmark: false,
                        selected: _f.status == s,
                        onSelected: (_) => setState(() => _f = _f.copyWith(status: s)),
                      ),
                  ]),
                ),
                section(
                  'Urutkan',
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, children: [
                      for (final s in _sortOrder)
                        ChoiceChip(
                          key: Key('sheet_sort_${s.name}'),
                          label: Text(s.label),
                          showCheckmark: false,
                          selected: _f.sort == s,
                          // Terdekat tanpa lokasi: nonaktif (abu-abu).
                          onSelected: s == GiveawaySort.nearest && !widget.locationKnown ? null : (_) => setState(() => _f = _f.copyWith(sort: s)),
                        ),
                    ]),
                    if (!widget.locationKnown) ...[
                      const SizedBox(height: 4),
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                        Text('Terdekat: Butuh lokasi', key: const Key('sort_nearest_hint'), style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
                        if (widget.onUseLocation != null)
                          TextButton(
                            key: const Key('sheet_use_location'),
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onUseLocation!();
                            },
                            child: const Text('Gunakan lokasi saya'),
                          ),
                      ]),
                    ],
                  ]),
                ),
                section(
                  'Kategori',
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(
                      label: const Text('Semua'),
                      showCheckmark: false,
                      selected: _f.category == null,
                      onSelected: (_) => setState(() => _f = _f.copyWith(category: null)),
                    ),
                    for (final c in giveawayCategories)
                      ChoiceChip(
                        key: Key('cat_$c'),
                        label: Text(categoryLabel(c)),
                        showCheckmark: false,
                        selected: _f.category == c,
                        onSelected: (_) => setState(() => _f = _f.copyWith(category: c)),
                      ),
                  ]),
                ),
                section(
                  'Deadline',
                  Wrap(spacing: 8, children: [
                    for (final (label, days) in _deadlineOptions)
                      ChoiceChip(
                        label: Text(label),
                        showCheckmark: false,
                        selected: _f.deadlineDays == days,
                        onSelected: (_) => setState(() => _f = _f.copyWith(deadlineDays: days)),
                      ),
                  ]),
                ),
                section(
                  'Nilai hadiah (${_code == 'IDR' ? 'Rp' : _code})',
                  Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('min_value'),
                        controller: _min,
                        inputFormatters: [DecimalInputFormatter(decimals: _decimals)],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Minimum'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('max_value'),
                        controller: _max,
                        inputFormatters: [DecimalInputFormatter(decimals: _decimals)],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Maksimum'),
                      ),
                    ),
                  ]),
                ),
                if (_f.nearby)
                  section(
                    'Radius',
                    Wrap(spacing: 8, children: [
                      for (final km in const [5, 10, 25])
                        ChoiceChip(
                          key: Key('radius_$km'),
                          label: Text('$km km'),
                          showCheckmark: false,
                          selected: _f.nearbyRadiusKm == km,
                          onSelected: (_) => setState(() => _f = _f.copyWith(nearbyRadiusKm: km)),
                        ),
                    ]),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  InlineMessage(_error!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.s16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: PrimaryButton(
            key: const Key('reset_filter'),
            label: 'Atur ulang',
            variant: ButtonVariant.text,
            expand: false,
            onPressed: () => Navigator.pop(
              context,
              widget.initial.copyWith(
                category: null, minValueIdr: null, maxValueIdr: null, deadlineDays: null,
                status: null, sort: GiveawaySort.deadline,
              ),
            ),
            ),
          ),
          const SizedBox(width: Spacing.s8),
          Flexible(child: PrimaryButton(key: const Key('apply_filter'), label: 'Terapkan', expand: false, onPressed: _apply)),
        ]),
      ],
    ),
    );
  }
}
