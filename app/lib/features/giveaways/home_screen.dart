import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../discover/discover_controller.dart';
import '../discover/discover_filters.dart' show categoryLabel;
import '../notifications/notification_bell.dart';
import '../notifications/notification_permission.dart';
import '../notifications/notifications_controller.dart';
import '../profile/user_avatar.dart';
import '../tickets/tickets_controller.dart';
import 'affinity_controller.dart';
import 'giveaway_card.dart';
import 'giveaway_models.dart';
import 'giveaways_controller.dart';

/// Lebar kartu di carousel horizontal (dp).
const double _carouselCardWidth = 264;

/// Giveaway "Segera draw": belum diundi dan jadwal drawnya masih di depan, paling dekat dulu.
List<Giveaway> soonestDraws(List<Giveaway> items, DateTime now, {int limit = 6}) {
  final soon = [
    for (final g in items)
      if (g.drawAt != null && g.drawAt!.isAfter(now) && g.phaseAt(now) != GiveawayPhase.drawn) g,
  ]..sort((a, b) => a.drawAt!.compareTo(b.drawAt!));
  return soon.take(limit).toList();
}

/// S-HOME (pusat fitur): sapaan, ringkasan tiket, kolom cari, tombol utama Input Code, grid "Menu fitur", chip kategori,
/// carousel "Segera draw" dan "Terdekat", lalu semua giveaway. Layar fitur dibuka dengan push (layar penuh, tombol kembali
/// ke Home). Carousel memakai data yang sudah dimuat controller (tanpa permintaan jaringan baru).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _category;

  @override
  void initState() {
    super.initState();
    final c = context.read<GiveawaysController>();
    if (c.state == LoadState.idle) Future.microtask(c.load);
    // Ringkasan tiket memakai TicketsController yang sama dengan My Tickets; dimuat sekali bila belum.
    final tickets = context.read<TicketsController?>();
    if (tickets != null && tickets.state == LoadState.idle) Future.microtask(tickets.load);
    // Minat per kategori untuk "Untuk kamu": dimuat sekali saat Home pertama dibuka.
    final affinity = context.read<AffinityController?>();
    if (affinity != null) Future.microtask(affinity.loadOnce);
    // Hitungan notifikasi: saat Home dibuka dan saat app kembali ke foreground (tanpa polling).
    WidgetsBinding.instance.addObserver(this);
    final notifs = context.read<NotificationsController?>();
    if (notifs != null) Future.microtask(notifs.refreshUnread);
    // Izin notifikasi sistem: sekali, dengan dialog penjelasan dulu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) promptNotificationPermissionOnce(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<NotificationsController?>()?.refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GiveawaysController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (c.state) {
          LoadState.idle || LoadState.loading when c.items.isEmpty => const _HomeSkeleton(),
          LoadState.error when c.items.isEmpty => ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.load),
          _ => Column(children: [
              if (c.offline) OfflineBanner(cachedAt: c.cachedAt),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await c.load();
                    if (c.state == LoadState.error && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.error ?? 'Gagal memuat.')));
                    }
                  },
                  child: _content(context, c),
                ),
              ),
            ]),
        },
      ),
    );
  }

  Widget _content(BuildContext context, GiveawaysController c) {
    final now = DateTime.now();
    final categories = {for (final g in c.items) g.category}.toList()..sort();
    final selected = categories.contains(_category) ? _category : null;
    final visible = [for (final g in c.items) if (selected == null || g.category == selected) g];
    final discover = context.watch<DiscoverController?>();
    final nearby = discover == null || !discover.filters.nearby
        ? const <Giveaway>[]
        : ([for (final g in discover.items) if (g.distanceKm != null && (selected == null || g.category == selected)) g]
          ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!)));
    final soon = soonestDraws(visible, now);
    final affinityScores = context.watch<AffinityController?>()?.scores ?? const {};
    final forYou = recommendFor(visible, affinityScores, now);
    void open(Giveaway g) => context.push('/giveaway/${g.id}', extra: g);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: _Header()),
        const SliverToBoxAdapter(child: _TicketSummary()),
        const SliverToBoxAdapter(child: _SearchBar()),
        const SliverToBoxAdapter(child: _InputCodeButton()),
        const SliverToBoxAdapter(child: _FeatureMenu()),
        if (categories.length > 1)
          SliverToBoxAdapter(
            child: _CategoryChips(categories: categories, selected: selected, onSelected: (v) => setState(() => _category = v)),
          ),
        if (forYou.isNotEmpty) ...[
          const SliverToBoxAdapter(
            key: Key('for_you'),
            child: SectionHeader('Untuk kamu', padding: EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.s8, 0)),
          ),
          SliverToBoxAdapter(
            child: _Carousel(
              items: forYou,
              onOpen: open,
              reasonsFor: (g) => recommendationReasons(g, affinityScores, now),
            ),
          ),
        ],
        if (soon.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader('Segera draw',
                padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.s8, 0),
                actionLabel: 'Lihat semua',
                onAction: () => context.push('/discover')),
          ),
          SliverToBoxAdapter(child: _Carousel(items: soon, onOpen: open)),
        ],
        if (nearby.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader('Terdekat',
                padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.s8, 0),
                actionLabel: 'Lihat semua',
                onAction: () => context.push('/discover')),
          ),
          SliverToBoxAdapter(child: _Carousel(items: nearby.take(6).toList(), onOpen: open)),
        ],
        const SliverToBoxAdapter(
          child: SectionHeader('Semua giveaway', padding: EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.screen, 0)),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.card_giftcard,
              title: 'Belum ada giveaway aktif',
              message: 'Tarik ke bawah untuk memuat ulang.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.listBottom),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: Spacing.cardGap),
              itemBuilder: (_, i) => GiveawayCard(giveaway: visible[i], onTap: () => open(visible[i])),
            ),
          ),
      ],
    );
  }
}

/// Sapaan + avatar kecil (ketuk -> Profil).
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController?>()?.user;
    final theme = Theme.of(context);
    final first = (user?.fullName.trim() ?? '').split(RegExp(r'\s+')).first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.screen, Spacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Halo,', style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
                Text(first.isEmpty ? 'Selamat datang' : first,
                    key: const Key('home_greeting'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
              ],
            ),
          ),
          const NotificationBell(),
          Semantics(
            button: true,
            label: 'Buka profil',
            child: InkResponse(
              onTap: () => context.go('/profile'),
              radius: kMinTap / 2 + 4,
              child: Padding(padding: const EdgeInsets.all(Spacing.s4), child: UserAvatar(user: user, radius: 20)),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Kamu punya N tiket" (ketuk -> My Tickets).
class _TicketSummary extends StatelessWidget {
  const _TicketSummary();
  @override
  Widget build(BuildContext context) {
    final tickets = context.watch<TicketsController?>();
    final c = context.colors;
    final theme = Theme.of(context);
    final n = tickets?.items.length;
    final title = n == null || (n == 0 && tickets!.state != LoadState.loaded)
        ? 'Tiketmu'
        : n == 0
            ? 'Belum ada tiket'
            : 'Kamu punya $n tiket';
    final subtitle = n == 0 && tickets!.state == LoadState.loaded
        ? 'Masukkan kode untuk mendapatkan tiket pertamamu'
        : 'Ketuk untuk melihat semua tiketmu';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.screen),
      child: SurfaceCard(
        key: const Key('ticket_summary'),
        onTap: () => context.push('/tickets'),
        color: c.primaryContainer,
        child: Row(
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                child: SizedBox(width: 44, height: 44, child: Icon(Icons.confirmation_number, color: c.onPrimary)),
              ),
            ),
            const SizedBox(width: Spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(color: c.onPrimaryContainer)),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: c.onPrimaryContainer)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

/// Kolom cari palsu: ketuk membuka Discover.
class _SearchBar extends StatelessWidget {
  const _SearchBar();
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.screen, 0),
      child: Semantics(
        button: true,
        label: 'Cari giveaway',
        excludeSemantics: true,
        onTap: () => context.push('/discover'),
        child: Material(
          color: c.surfaceVariant,
          borderRadius: Radii.inputAll,
          child: InkWell(
            key: const Key('home_search'),
            borderRadius: Radii.inputAll,
            onTap: () => context.push('/discover'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
                child: Row(children: [
                  Icon(Icons.search, color: c.mutedOnVariant),
                  const SizedBox(width: Spacing.s12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.s12),
                      child: Text('Cari giveaway, hadiah, atau penyelenggara', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.mutedOnVariant)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aksi utama Home: Input Code (satu-satunya tombol utama di layar ini).
class _InputCodeButton extends StatelessWidget {
  const _InputCodeButton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.screen, 0),
        child: PrimaryButton(key: const Key('home_input_code'), label: 'Input Code', icon: Icons.qr_code_2, onPressed: () => context.push('/code')),
      );
}

/// Menu fitur: (kunci, ikon, label, rute). Urutan = urutan tampil.
const _featureMenu = [
  ('discover', Icons.explore_outlined, 'Discover', '/discover'),
  ('tickets', Icons.confirmation_number_outlined, 'My Tickets', '/tickets'),
  ('assistant', Icons.smart_toy_outlined, 'Asisten', '/assistant'),
  ('game', Icons.sports_esports_outlined, 'Game', '/game'),
  ('converter', Icons.currency_exchange, 'Konverter', '/converter'),
  ('map', Icons.map_outlined, 'Peta', '/map'),
];

/// Grid "Menu fitur": 4 kolom bila tiap kotak cukup lebar untuk label (memperhitungkan skala font), selain itu 2 kolom.
class _FeatureMenu extends StatelessWidget {
  const _FeatureMenu();

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Menu fitur', padding: EdgeInsets.fromLTRB(Spacing.screen, Spacing.s16, Spacing.screen, Spacing.s8)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.screen),
          child: LayoutBuilder(builder: (context, box) {
            final cols = (box.maxWidth - Spacing.s8 * 3) / 4 >= 72 * scale ? 4 : 2;
            return Column(children: [
              for (var start = 0; start < _featureMenu.length; start += cols)
                Padding(
                  padding: EdgeInsets.only(top: start == 0 ? 0 : Spacing.s8),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = start; i < start + cols; i++) ...[
                        if (i > start) const SizedBox(width: Spacing.s8),
                        Expanded(child: i < _featureMenu.length ? _FeatureTile(_featureMenu[i]) : const SizedBox.shrink()),
                      ],
                    ]),
                  ),
                ),
            ]);
          }),
        ),
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.item);
  final (String, IconData, String, String) item;

  @override
  Widget build(BuildContext context) {
    final (key, icon, label, route) = item;
    final c = context.colors;
    return SurfaceCard(
      key: Key('menu_$key'),
      onTap: () => context.push(route),
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(vertical: Spacing.s12, horizontal: Spacing.s4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          DecoratedBox(
            decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
            child: SizedBox(width: 40, height: 40, child: Icon(icon, color: c.onPrimaryContainer)),
          ),
          const SizedBox(height: Spacing.s8),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
        ]),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.categories, required this.selected, required this.onSelected});
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s12),
      child: SizedBox(
        height: kMinTap,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.screen),
          children: [
            ChoiceChip(label: const Text('Semua'), selected: selected == null, showCheckmark: false, onSelected: (_) => onSelected(null)),
            for (final cat in categories) ...[
              const SizedBox(width: Spacing.s8),
              ChoiceChip(
                key: Key('home_cat_$cat'),
                label: Text(categoryLabel(cat)),
                selected: selected == cat,
                showCheckmark: false,
                onSelected: (_) => onSelected(selected == cat ? null : cat),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kartu horizontal. Tinggi mengikuti kartu tertinggi (IntrinsicHeight), jadi aman untuk skala font besar.
class _Carousel extends StatelessWidget {
  const _Carousel({required this.items, required this.onOpen, this.reasonsFor});
  final List<Giveaway> items;
  final void Function(Giveaway) onOpen;
  final List<String> Function(Giveaway)? reasonsFor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, g) in items.indexed) ...[
              if (i > 0) const SizedBox(width: Spacing.cardGap),
              SizedBox(
                width: _carouselCardWidth,
                child: GiveawayCard(
                  giveaway: g,
                  variant: GiveawayCardVariant.carousel,
                  onTap: () => onOpen(g),
                  reasons: reasonsFor?.call(g),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Column(children: [
          _Header(),
          SkeletonLoader(shrinkWrap: true, count: 2),
        ]),
      );
}
