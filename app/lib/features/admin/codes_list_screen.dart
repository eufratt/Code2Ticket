import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_models.dart';
import 'admin_controller.dart';
import 'admin_models.dart';

/// Daftar Kode (GET /admin/giveaways/:id/codes): kode + status (belum dipakai / dipakai). Backend mengirim kode
/// lengkap kepada admin, jadi tampil apa adanya; hanya di memori layar, tidak disimpan.
class CodesListScreen extends StatefulWidget {
  const CodesListScreen({super.key, required this.giveawayId, this.giveaway});
  final String giveawayId;
  final Giveaway? giveaway;

  @override
  State<CodesListScreen> createState() => _CodesListScreenState();
}

class _CodesListScreenState extends State<CodesListScreen> {
  List<AdminCode>? _codes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _codes = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await context.read<AdminController>().listCodes(widget.giveawayId);
    if (r == null || !mounted) return;
    setState(() {
      _loading = false;
      if (r.isOk) {
        _codes = r.data;
      } else {
        _error = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final codes = _codes;
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Kode')),
      body: _loading && codes == null
          ? const SkeletonLoader(shape: SkeletonShape.ticket, count: 4)
          : _error != null && codes == null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: codes == null || codes.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 420, child: EmptyState(icon: Icons.vpn_key_outlined, title: 'Belum ada kode', message: 'Buat kode lewat Generate Code.')),
                        ])
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
                          children: [
                            if (widget.giveaway != null) Text(widget.giveaway!.title, style: Theme.of(context).textTheme.titleMedium),
                            SectionHeader('${codes.length} kode, ${codes.where((c) => c.isUsed).length} dipakai'),
                            for (final c in codes) Padding(padding: const EdgeInsets.only(bottom: Spacing.s8), child: _CodeRow(code: c)),
                          ],
                        ),
                ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code});
  final AdminCode code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      key: Key('code_${code.code}'),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code.code, style: AppTypography.mono(theme.textTheme.titleMedium!).copyWith(letterSpacing: 1)),
                if (code.isUsed && code.usedAt != null)
                  Text('Dipakai ${context.when(code.usedAt!)}', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
                if (code.geoRadiusKm != null)
                  Text('Radius ${code.geoRadiusKm!.toStringAsFixed(code.geoRadiusKm! % 1 == 0 ? 0 : 1)} km', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
              ],
            ),
          ),
          const SizedBox(width: Spacing.s8),
          code.isUsed
              ? const StatusChip.custom(label: 'Dipakai', tone: StatusTone.neutral, icon: Icons.check)
              : const StatusChip.custom(label: 'Belum dipakai', tone: StatusTone.success, icon: Icons.fiber_manual_record),
        ],
      ),
    );
  }
}
