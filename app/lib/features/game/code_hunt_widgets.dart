import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/category_style.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/affinity_controller.dart';
import '../giveaways/giveaways_controller.dart';
import '../tickets/tickets_controller.dart';
import 'code_hunt.dart';

const practiceDisclaimer = 'Tiket latihan: tidak memengaruhi peluang menang';

/// Target latihan dari data yang sudah dimuat (tiket pengguna, daftar giveaway, afinitas); tanpa permintaan jaringan.
/// Controller yang tidak ada di pohon widget (mis. tes) = null -> tampilan generik.
PracticeTarget? practiceTargetOf(BuildContext context, {bool listen = false}) {
  T? get<T>() => listen ? context.watch<T?>() : context.read<T?>();
  return PracticeTarget.pick(
    tickets: get<TicketsController>()?.items ?? const [],
    giveaways: get<GiveawaysController>()?.items ?? const [],
    affinity: get<AffinityController>()?.scores ?? const {},
    now: DateTime.now(),
  );
}

/// Teks yang dibaca pembaca layar: segmen terisi dieja per karakter, sisanya disebut kosong.
String codeSemanticLabel(List<String> segments, int filled) {
  final f = filled.clamp(0, segments.length);
  final spelled = segments.take(f).map((s) => s.split('').join(' ')).join(', ');
  return 'Kode ${segments.length} segmen, $f terisi${f > 0 ? ': $spelled' : ''}';
}

/// Baris "Latihan untuk: {judul}" atau teks generik bila belum ada data.
class PracticeTargetLine extends StatelessWidget {
  const PracticeTargetLine({super.key, required this.target, this.center = false});
  final PracticeTarget? target;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = target;
    final style = CategoryStyle.of(t?.category);
    return Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: style.gradient, borderRadius: Radii.buttonAll),
            child: SizedBox(width: 32, height: 32, child: Icon(style.icon, color: Overlays.onGradient, size: 18)),
          ),
        ),
        const SizedBox(width: Spacing.s8),
        Flexible(
          child: Text(
            t == null ? 'Latihan merakit kode menjadi tiket' : 'Latihan untuk: ${t.title}',
            key: const Key('practice_target'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onBackground, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Kode rakitan XXXX-XXXX-XXXX yang terisi bertahap; slot kosong "····". Tidak terpotong: tiap baris mengecil bila perlu.
class CodeDisplay extends StatelessWidget {
  const CodeDisplay({super.key, required this.segments, required this.filled, this.align = CrossAxisAlignment.start});
  final List<String> segments;
  final int filled;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = AppTypography.mono(Theme.of(context).textTheme.titleMedium!);
    final f = filled.clamp(0, segments.length);
    final rows = <Widget>[];
    for (var i = 0; i < segments.length; i += 3) {
      final spans = <InlineSpan>[];
      for (var j = i; j < i + 3 && j < segments.length; j++) {
        if (j > i) spans.add(TextSpan(text: '-', style: TextStyle(color: c.mutedOnVariant)));
        spans.add(j < f
            ? TextSpan(text: segments[j], style: TextStyle(color: c.onBackground, fontWeight: FontWeight.w700))
            : TextSpan(text: emptySegment, style: TextStyle(color: c.mutedOnVariant)));
      }
      rows.add(FittedBox(fit: BoxFit.scaleDown, child: Text.rich(TextSpan(children: spans), maxLines: 1, softWrap: false, style: base)));
    }
    return Semantics(
      label: codeSemanticLabel(segments, f),
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: align, children: rows),
    );
  }
}

/// Tiket Latihan bergaya TicketCard: kode rakitan, nomor latihan, kategori giveaway target, dan label tegas bahwa ini bukan tiket asli.
class PracticeTicket extends StatelessWidget {
  const PracticeTicket({super.key, required this.segments, required this.number, required this.target});
  final List<String> segments;
  final String number;
  final PracticeTarget? target;

  @override
  Widget build(BuildContext context) {
    final code = codeRows(segments, segments.length);
    return Semantics(
      container: true,
      label: 'Tiket latihan nomor $number. ${target == null ? '' : 'Latihan untuk ${target!.title}. '}Kode rakitan: ${segments.map((s) => s.split('').join(' ')).join(', ')}. $practiceDisclaimer.',
      child: ExcludeSemantics(
        child: TicketCard(
          key: const Key('practice_ticket'),
          title: 'Tiket Latihan',
          category: target?.category,
          ticketNumber: number,
          numberKey: const Key('practice_ticket_number'),
          status: AppStatus.ticketEligible,
          statusWidget: const StatusChip.custom(label: 'Latihan', tone: StatusTone.neutral, icon: Icons.school_outlined),
          prizeText: code.join('\n'),
          subtitle: target == null ? 'Kode latihan, bukan kode redeem' : 'Latihan untuk: ${target!.title}',
        ),
      ),
    );
  }
}
