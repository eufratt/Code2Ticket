import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../widgets/state_views.dart';
import 'giveaway_card.dart';
import 'giveaways_controller.dart';

/// S-HOME: giveaway aktif. Ringkasan tiket, nearby, dan rekomendasi menyusul (M4/M7).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final c = context.read<GiveawaysController>();
    if (c.state == LoadState.idle) Future.microtask(c.load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GiveawaysController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Code2Ticket')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.items.isEmpty => const LoadingView(),
        LoadState.error when c.items.isEmpty =>
          ErrorRetryView(message: c.error ?? 'Gagal memuat.', onRetry: c.load),
        _ => RefreshIndicator(
            onRefresh: () async {
              await c.load();
              if (c.state == LoadState.error && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.error ?? 'Gagal memuat.')));
              }
            },
            child: c.items.isEmpty
                ? ListView(children: const [
                    SizedBox(
                      height: 360,
                      child: EmptyView(
                        icon: Icons.card_giftcard,
                        message: 'Belum ada giveaway aktif.\nTarik ke bawah untuk memuat ulang.',
                      ),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 140),
                    itemCount: c.items.length,
                    itemBuilder: (_, i) => GiveawayCard(
                      giveaway: c.items[i],
                      onTap: () => context.push('/giveaway/${c.items[i].id}', extra: c.items[i]),
                    ),
                  ),
          ),
      },
    );
  }
}
