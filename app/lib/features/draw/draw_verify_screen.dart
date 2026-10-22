import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/verify/chain_verifier.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'draw_controller.dart';

/// Hash panjang dipotong: "a1b2c3d4…9f8e7d6c". Nilai pendek (mis. daftar tiket pemenang) ditampilkan utuh.
String shortHash(String h) => h.length <= 20 ? h : '${h.substring(0, 8)}…${h.substring(h.length - 8)}';

/// Judul dan penjelasan awam tiap langkah.
const _stepTexts = <VerifyStepId, (String, String)>{
  VerifyStepId.commit: (
    'Seed dikunci sebelum tiket terbit',
    'Sebelum ada yang ikut, panitia mengunci seed rahasia lewat hash-nya. Hasil tidak bisa diatur setelah tahu siapa pesertanya.',
  ),
  VerifyStepId.chain: (
    'Rantai hash tersambung',
    'Tiap catatan memuat hash catatan sebelumnya. Mengubah satu catatan saja akan memutus rantai.',
  ),
  VerifyStepId.seed: (
    'Seed cocok dengan komitmen',
    'Setelah draw, seed dibuka. App men-hash ulang seed itu dan membandingkannya dengan komitmen tadi.',
  ),
  VerifyStepId.winners: (
    'Pemenang dihitung ulang',
    'Dari seed dan daftar tiket, app menghitung sendiri pemenangnya di ponselmu, lalu membandingkannya dengan hasil server.',
  ),
};

/// S-VERIFY "Cek keaslian": semua perhitungan hash dilakukan di perangkat dari data mentah server; tiap langkah
/// berstatus Lulus / Gagal / Belum dicek (teks + ikon, bukan hanya warna), lalu ringkasan Terverifikasi / Tidak cocok.
class DrawVerifyScreen extends StatefulWidget {
  const DrawVerifyScreen({super.key, required this.giveawayId, this.runner});
  final String giveawayId;

  /// Hanya untuk tes: pengganti isolate untuk perhitungan hash.
  final VerifyRunner? runner;

  @override
  State<DrawVerifyScreen> createState() => _DrawVerifyScreenState();
}

class _DrawVerifyScreenState extends State<DrawVerifyScreen> {
  late final DrawController _draw = DrawController(context.read<AuthedApi>(), widget.giveawayId, runner: widget.runner, verifyOnly: true);

  @override
  void initState() {
    super.initState();
    Future.microtask(_draw.load);
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _draw,
      builder: (context, _) {
        final d = _draw;
        return Scaffold(
          appBar: AppBar(title: const Text('Cek Keaslian')),
          body: switch (d.state) {
            LoadState.idle || LoadState.loading => const SkeletonLoader(shape: SkeletonShape.ticket, count: 4),
            LoadState.error => ErrorState(
                title: d.error == verifyOfflineMessage ? 'Sedang offline' : 'Gagal memuat',
                message: d.error ?? 'Gagal memuat.',
                onRetry: d.load,
              ),
            LoadState.loaded => _Steps(report: d.report!),
          },
        );
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.report});
  final VerificationReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
      children: [
        Text(
          'Kamu tidak perlu percaya begitu saja pada server. App menghitung ulang semuanya di ponselmu.',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: Spacing.s16),
        for (var i = 0; i < report.steps.length; i++) ...[
          _StepCard(number: i + 1, step: report.steps[i]),
          const SizedBox(height: Spacing.cardGap),
        ],
        _Summary(report: report),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.step});
  final int number;
  final VerifyStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final (title, why) = _stepTexts[step.id]!;
    final chip = switch (step.status) {
      StepStatus.pass => const StatusChip.custom(label: 'Lulus', tone: StatusTone.success, icon: Icons.check_circle),
      StepStatus.fail => const StatusChip.custom(label: 'Gagal', tone: StatusTone.error, icon: Icons.cancel),
      StepStatus.skipped => const StatusChip.custom(label: 'Belum dicek', tone: StatusTone.neutral, icon: Icons.remove_circle_outline),
    };
    return SurfaceCard(
      key: Key('verify_step_${step.id.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
                  child: SizedBox(width: 32, height: 32, child: Center(child: Text('$number', style: theme.textTheme.titleSmall?.copyWith(color: c.onPrimaryContainer)))),
                ),
              ),
              const SizedBox(width: Spacing.s12),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Spacing.s8),
          Align(alignment: Alignment.centerLeft, child: chip),
          const SizedBox(height: Spacing.s8),
          Text(why, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: Spacing.s8),
          Semantics(liveRegion: true, child: Text(step.detail, style: theme.textTheme.bodyMedium)),
          for (final e in step.evidence) _HashRow(label: e.label, value: e.value, stepId: step.id),
        ],
      ),
    );
  }
}

class _HashRow extends StatelessWidget {
  const _HashRow({required this.label, required this.value, required this.stepId});
  final String label, value;
  final VerifyStepId stepId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
                Text(shortHash(value), key: Key('hash_${stepId.name}_$label'), style: AppTypography.mono(theme.textTheme.bodyMedium!)),
              ],
            ),
          ),
          IconButton(
            key: Key('copy_${stepId.name}_$label'),
            tooltip: 'Salin $label',
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: value));
              messenger.showSnackBar(SnackBar(content: Text('$label disalin.')));
            },
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report});
  final VerificationReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (chip, text) = report.verified
        ? (const StatusChip(AppStatus.verified), 'Semua pemeriksaan lulus. Hasil draw ini tidak diubah sejak seed dikunci.')
        : report.mismatch
            ? (const StatusChip(AppStatus.mismatch), 'Ada pemeriksaan yang gagal, jadi hasil ini tidak bisa dipercaya. Laporkan lewat Saran & Kesan.')
            : (const StatusChip.custom(label: 'Belum diundi', tone: StatusTone.neutral, icon: Icons.hourglass_top), 'Draw belum berjalan, jadi seed dan pemenang belum bisa diperiksa. Rantai dan komitmen sudah lulus.');
    return SurfaceCard(
      key: const Key('verify_summary'),
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text('Ringkasan', style: theme.textTheme.titleMedium)),
          const SizedBox(height: Spacing.s8),
          Align(alignment: Alignment.centerLeft, child: chip),
          const SizedBox(height: Spacing.s8),
          Semantics(liveRegion: true, child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
