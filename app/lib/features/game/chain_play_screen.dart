import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import 'chain_levels_screen.dart' show chainStoreOf;
import 'chain_puzzle.dart';

const chainExplanation =
    'Inilah yang dilakukan layar Verifikasi pada undian asli: menghitung ulang hash tiap block dan memastikan rantainya bersambung.';

/// Layar satu level Rakit Rantai: mode Susun (urutkan block) atau Periksa (temukan block yang dipalsukan).
/// Logika ada di chain_puzzle.dart; layar hanya menyajikan. Tidak ada XP, lencana, atau skor ke server.
class ChainPlayScreen extends StatefulWidget {
  const ChainPlayScreen({super.key, required this.levelNumber});
  final int levelNumber;
  @override
  State<ChainPlayScreen> createState() => _ChainPlayScreenState();
}

class _ChainPlayScreenState extends State<ChainPlayScreen> {
  late final ChainLevel _level = ChainLevel.all[(widget.levelNumber - 1).clamp(0, ChainLevel.all.length - 1)];
  late final ChainPuzzle _puzzle = ChainPuzzle.generate(_level);
  late List<ChainBlock> _order = List.of(_puzzle.shuffled);
  int _steps = 0;
  List<bool>? _marks; // hasil "Cek Rantai" (per posisi); hilang saat urutan berubah
  bool _won = false;
  int? _tapped; // mode Periksa: posisi block yang terakhir diketuk
  ChainProgress? _progress;

  bool get _arrange => _level.mode == ChainMode.arrange;

  void _move(int from, int to) {
    if (_won || to < 0 || to >= _order.length) return;
    final next = List.of(_order);
    next.insert(to, next.removeAt(from));
    setState(() {
      _order = next;
      _steps++;
      _marks = null;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex != oldIndex) _move(oldIndex, newIndex);
  }

  Future<void> _check() async {
    final marks = checkChain(_order);
    setState(() {
      _marks = marks;
      _won = marks.every((x) => x);
    });
    if (_won) await _finish();
  }

  Future<void> _tap(int pos) async {
    if (_won) return;
    final found = !_order[pos].hashMatches;
    setState(() {
      _tapped = pos;
      _steps++;
      _won = found;
    });
    if (found) await _finish();
  }

  Future<void> _finish() async {
    final p = await chainStoreOf(context).record(_level.number, _steps);
    if (mounted) setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final hasNext = _level.number < ChainLevel.all.length;
    return Scaffold(
      appBar: AppBar(title: Text('Rakit Rantai · ${_level.title}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          Text(
            _arrange
                ? 'Susun block dari yang pertama: block pertama memakai previous hash genesis (00000000), dan previous hash tiap block sama dengan hash block sebelumnya. Seret gagang atau pakai tombol naik/turun.'
                : 'Rantai ini sudah berurutan. Satu block isinya diubah setelah hash-nya dicatat. Ketuk block yang kamu curigai.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.s12),
          Semantics(
            liveRegion: true,
            child: Text(_arrange ? 'Langkah: $_steps' : 'Percobaan: $_steps', key: const Key('chain_steps'), style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: Spacing.s8),
          if (_arrange) _arrangeList() else _inspectList(),
          const SizedBox(height: Spacing.s12),
          if (_arrange && !_won) PrimaryButton(key: const Key('chain_check'), label: 'Cek Rantai', icon: Icons.fact_check_outlined, onPressed: _check),
          if (_arrange && !_won && _marks != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s8),
              child: InlineMessage('${_marks!.where((x) => x).length} dari ${_marks!.length} block sudah di posisi yang benar.', tone: StatusTone.info),
            ),
          if (!_arrange && _tapped != null && !_won)
            const InlineMessage(
              'Hash block itu cocok dengan hasil hitung ulang. Petunjuk: hitung ulang SHA-256(previous_hash|payload) dan bandingkan dengan hash tersimpan. Coba block lain.',
              tone: StatusTone.warning,
            ),
          if (!_arrange && _tapped != null) _Compare(block: _order[_tapped!]),
          if (_won) ...[
            const SizedBox(height: Spacing.s12),
            InlineMessage(
              _arrange ? 'Rantai bersambung! Selesai dalam $_steps langkah.' : 'Tidak valid: hash block tidak cocok',
              tone: StatusTone.success,
            ),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s8),
                child: Text('Langkah terbaik level ini: ${_progress!.best[_level.number]}', key: const Key('chain_best'), style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: Spacing.s12),
            SurfaceCard(
              key: const Key('chain_explain'),
              color: c.primaryContainer,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(child: Icon(Icons.verified_outlined, color: c.onPrimaryContainer)),
                const SizedBox(width: Spacing.s12),
                Expanded(child: Text(chainExplanation, style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer))),
              ]),
            ),
            const SizedBox(height: Spacing.s12),
            if (hasNext)
              PrimaryButton(
                key: const Key('chain_next'),
                label: 'Level berikutnya',
                icon: Icons.arrow_forward,
                onPressed: () => context.pushReplacement('/game/chain/play', extra: _level.number + 1),
              ),
            PrimaryButton(key: const Key('chain_done'), label: 'Selesai', variant: hasNext ? ButtonVariant.text : ButtonVariant.primary, onPressed: () => context.pop()),
          ],
        ],
      ),
    );
  }

  Widget _arrangeList() => ReorderableListView.builder(
        key: const Key('chain_list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _order.length,
        onReorderItem: _reorder,
        itemBuilder: (context, i) {
          final b = _order[i];
          final ok = _marks?[i];
          return Padding(
            key: ValueKey(b.hash),
            padding: const EdgeInsets.only(bottom: Spacing.cardGap),
            child: _BlockCard(
              block: b,
              position: i + 1,
              status: ok == null ? null : (ok ? _BlockStatus.right : _BlockStatus.wrong),
              leading: _won
                  ? null
                  : ReorderableDragStartListener(
                      index: i,
                      child: SizedBox(width: 40, height: 48, child: Icon(Icons.drag_indicator, color: context.colors.muted, semanticLabel: 'Seret untuk memindahkan')),
                    ),
              trailing: _won
                  ? null
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(key: Key('chain_up_$i'), tooltip: 'Naikkan block ${b.payload}', onPressed: i == 0 ? null : () => _move(i, i - 1), icon: const Icon(Icons.keyboard_arrow_up)),
                      IconButton(key: Key('chain_down_$i'), tooltip: 'Turunkan block ${b.payload}', onPressed: i == _order.length - 1 ? null : () => _move(i, i + 1), icon: const Icon(Icons.keyboard_arrow_down)),
                    ]),
            ),
          );
        },
      );

  Widget _inspectList() => Column(children: [
        for (var i = 0; i < _order.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.cardGap),
            child: _BlockCard(
              key: Key('chain_block_$i'),
              block: _order[i],
              position: i + 1,
              status: _tapped == i ? (_order[i].hashMatches ? _BlockStatus.matches : _BlockStatus.mismatch) : null,
              onTap: _won ? null : () => _tap(i),
            ),
          ),
      ]);
}

enum _BlockStatus {
  right('Posisi benar', StatusTone.success, Icons.check_circle_outline),
  wrong('Posisi salah', StatusTone.error, Icons.cancel_outlined),
  matches('Hash cocok', StatusTone.success, Icons.check_circle_outline),
  mismatch('Hash tidak cocok', StatusTone.error, Icons.cancel_outlined);

  const _BlockStatus(this.label, this.tone, this.icon);
  final String label;
  final StatusTone tone;
  final IconData icon;
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({super.key, required this.block, required this.position, this.status, this.leading, this.trailing, this.onTap});
  final ChainBlock block;
  final int position;
  final _BlockStatus? status;
  final Widget? leading, trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final mono = AppTypography.mono(theme.textTheme.bodyMedium!);
    final label = 'Block posisi $position, isi ${block.payload}, previous hash ${block.shortPrevious}, hash ${block.shortHash}${status == null ? '' : ', ${status!.label}'}';
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$position. ${block.payload}', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.s4),
      Wrap(spacing: Spacing.s12, children: [
        Text('prev: ${block.shortPrevious}', style: mono.copyWith(color: c.muted)),
        Text('hash: ${block.shortHash}', style: mono),
      ]),
      if (status != null) Padding(padding: const EdgeInsets.only(top: Spacing.s8), child: StatusChip.custom(label: status!.label, tone: status!.tone, icon: status!.icon)),
    ]);
    final body = Semantics(container: true, label: label, excludeSemantics: true, child: info);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s8, vertical: Spacing.s8),
      onTap: onTap,
      child: Row(children: [
        ?leading,
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: Spacing.s8), child: body)),
        ?trailing,
      ]),
    );
  }
}

/// Hash tersimpan vs hash hitung ulang untuk block yang diketuk (mode Periksa).
class _Compare extends StatelessWidget {
  const _Compare({required this.block});
  final ChainBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = AppTypography.mono(theme.textTheme.bodyMedium!);
    final ok = block.hashMatches;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8),
      child: SurfaceCard(
        key: const Key('chain_compare'),
        semanticLabel: 'Hash tersimpan ${block.shortHash}, hash hitung ulang ${block.shortRecomputed}, ${ok ? 'cocok' : 'tidak cocok'}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hash tersimpan', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
          Text(block.shortHash, key: const Key('chain_stored'), style: mono),
          const SizedBox(height: Spacing.s8),
          Text('Hash hitung ulang', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
          Text(block.shortRecomputed, key: const Key('chain_recomputed'), style: mono),
          const SizedBox(height: Spacing.s8),
          StatusChip.custom(label: ok ? 'Cocok' : 'Tidak cocok', tone: ok ? StatusTone.success : StatusTone.error, icon: ok ? Icons.check_circle_outline : Icons.cancel_outlined),
        ]),
      ),
    );
  }
}
