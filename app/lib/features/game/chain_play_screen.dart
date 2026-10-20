import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import 'chain_levels_screen.dart' show chainStoreOf;
import 'chain_puzzle.dart';

const chainExplanation =
    'Inilah yang dilakukan layar Verifikasi pada undian asli: menghitung ulang hash tiap block dan memastikan rantainya bersambung, '
    'yaitu "prev" tiap block sama dengan hash block sebelumnya.';

const howToArrange = 'Setiap block menyimpan hash block sebelumnya. Urutkan block sampai \'prev\' tiap block sama dengan \'hash\' block di atasnya.';
const howToInspect =
    'Kalau isi satu block diubah, hash-nya berubah dan sambungan ke block berikutnya putus. '
    'Bandingkan \'prev\' tiap block dengan \'hash\' block sebelumnya, lalu ketuk sambungan yang tidak cocok.';

/// Salah sebanyak ini -> tombol "Petunjuk" muncul (mode Periksa).
const hintAfterWrong = 2;

/// Penjelasan setelah sambungan putus ditemukan (mode Periksa).
String brokenExplanation(ChainPuzzle p) =>
    'Block ${p.brokenAfter! + 1} diubah, hash barunya ${p.newHash} tidak lagi sama dengan yang tersimpan di block berikutnya (${p.storedHash}). '
    'Karena itu rantai putus dan semua block sesudahnya ikut tidak valid.';

/// Layar satu level Rakit Rantai: mode Susun (urutkan block) atau Periksa (ketuk sambungan yang putus).
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
  bool _howTo = false;
  int _wrong = 0; // mode Periksa
  bool _hint = false;
  final Map<int, bool> _checked = {}; // mode Periksa: sambungan -> true bila putus
  ChainProgress? _progress;

  bool get _arrange => _level.mode == ChainMode.arrange;

  @override
  void initState() {
    super.initState();
    _loadHowTo();
  }

  /// Kartu "Cara main" terbuka otomatis pada kunjungan pertama ke mode ini.
  Future<void> _loadHowTo() async {
    final store = chainStoreOf(context);
    if (await store.howToSeen(_level.mode)) return;
    if (mounted) setState(() => _howTo = true);
    await store.markHowToSeen(_level.mode);
  }

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

  /// Mode Periksa: pemain mengetuk sambungan [i] (antara block i dan i+1).
  Future<void> _tapLink(int i) async {
    if (_won || _checked.containsKey(i)) return;
    final broken = !linkIntact(_order, i);
    setState(() {
      _checked[i] = broken;
      _steps++;
      if (broken) {
        _won = true;
      } else {
        _wrong++;
      }
    });
    if (broken) await _finish();
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
      appBar: AppBar(
        title: Text('Rakit Rantai · ${_level.title}'),
        actions: [
          IconButton(key: const Key('chain_help'), tooltip: 'Cara main', icon: const Icon(Icons.help_outline), onPressed: () => setState(() => _howTo = !_howTo)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          if (_howTo)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s12),
              child: SurfaceCard(
                key: const Key('chain_howto'),
                color: c.primaryContainer,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ExcludeSemantics(child: Icon(Icons.help_outline, color: c.onPrimaryContainer)),
                    const SizedBox(width: Spacing.s12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Semantics(header: true, child: Text('Cara main', style: theme.textTheme.titleMedium?.copyWith(color: c.onPrimaryContainer))),
                        const SizedBox(height: Spacing.s4),
                        Text(_arrange ? howToArrange : howToInspect, style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer)),
                      ]),
                    ),
                  ]),
                  PrimaryButton(key: const Key('chain_howto_close'), label: 'Mengerti', variant: ButtonVariant.text, expand: false, onPressed: () => setState(() => _howTo = false)),
                ]),
              ),
            ),
          Text(
            _arrange
                ? 'Block pertama memakai previous hash genesis (00000000). Seret gagang atau pakai tombol naik/turun.'
                : 'Rantai ini sudah berurutan. Ketuk "Sambungan putus?" di antara dua block yang menurutmu tidak cocok.',
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
          if (!_arrange && !_won && _wrong > 0)
            const InlineMessage(
              'Sambungan itu cocok: "prev" block bawah sama dengan "hash" block di atasnya. Bandingkan sambungan lain.',
              tone: StatusTone.warning,
            ),
          if (!_arrange && !_won && _wrong >= hintAfterWrong && !_hint)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s8),
              child: PrimaryButton(key: const Key('chain_hint'), label: 'Petunjuk', icon: Icons.lightbulb_outline, variant: ButtonVariant.secondary, onPressed: () => setState(() => _hint = true)),
            ),
          if (!_arrange && !_won && _hint)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.s8),
              child: InlineMessage('Sambungan yang putus ada di antara dua block bertanda "Periksa di sini".', tone: StatusTone.info),
            ),
          if (_won) ...[
            const SizedBox(height: Spacing.s12),
            if (_arrange)
              InlineMessage('Rantai bersambung! Selesai dalam $_steps langkah.', tone: StatusTone.success)
            else
              Semantics(liveRegion: true, child: InlineMessage(brokenExplanation(_puzzle), key: const Key('chain_broken_explain'), tone: StatusTone.success)),
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

  Widget _inspectList() {
    final t = _puzzle.brokenAfter!;
    bool hinted(int i) => _hint && !_won && (i == t || i == t + 1);
    return Column(children: [
      for (var i = 0; i < _order.length; i++) ...[
        _BlockCard(
          key: Key('chain_block_$i'),
          block: _order[i],
          position: i + 1,
          status: hinted(i) ? _BlockStatus.hint : null,
        ),
        if (i < _order.length - 1)
          _Connector(
            key: Key('chain_link_$i'),
            upper: i + 1,
            lower: i + 2,
            broken: _checked[i],
            onTap: _won || _checked.containsKey(i) ? null : () => _tapLink(i),
          ),
      ],
    ]);
  }
}

enum _BlockStatus {
  right('Posisi benar', StatusTone.success, Icons.check_circle_outline),
  wrong('Posisi salah', StatusTone.error, Icons.cancel_outlined),
  hint('Periksa di sini', StatusTone.info, Icons.search);

  const _BlockStatus(this.label, this.tone, this.icon);
  final String label;
  final StatusTone tone;
  final IconData icon;
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({super.key, required this.block, required this.position, this.status, this.leading, this.trailing});
  final ChainBlock block;
  final int position;
  final _BlockStatus? status;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final mono = AppTypography.mono(theme.textTheme.bodyMedium!);
    final label = 'Block posisi $position, isi ${block.payload}, prev ${block.shortPrevious}, hash ${block.shortHash}${status == null ? '' : ', ${status!.label}'}';
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$position. ${block.payload}', style: theme.textTheme.titleMedium),
      const SizedBox(height: Spacing.s4),
      Wrap(spacing: Spacing.s12, children: [
        Text('prev: ${block.shortPrevious}', style: mono.copyWith(color: c.muted)),
        Text('hash: ${block.shortHash}', style: mono),
      ]),
      if (status != null) Padding(padding: const EdgeInsets.only(top: Spacing.s8), child: StatusChip.custom(label: status!.label, tone: status!.tone, icon: status!.icon)),
    ]);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s8, vertical: Spacing.s8),
      child: Row(children: [
        ?leading,
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: Spacing.s8), child: Semantics(container: true, label: label, excludeSemantics: true, child: info))),
        ?trailing,
      ]),
    );
  }
}

/// Konektor di antara dua block (mode Periksa). Status selalu teks + ikon: belum diperiksa, cocok, atau putus.
class _Connector extends StatelessWidget {
  const _Connector({super.key, required this.upper, required this.lower, required this.broken, required this.onTap});
  final int upper, lower;
  final bool? broken; // null = belum diperiksa
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (text, icon, status) = switch (broken) {
      null => ('Sambungan putus?', Icons.link, 'belum diperiksa'),
      true => ('Sambungan putus', Icons.link_off, 'putus'),
      false => ('Sambungan cocok', Icons.link, 'cocok'),
    };
    final sc = broken == null ? null : StatusChip.colorsOf(c, broken! ? StatusTone.error : StatusTone.success);
    return Semantics(
      button: onTap != null,
      label: 'Sambungan antara block $upper dan block $lower, $status${onTap != null ? '. Ketuk jika prev block $lower tidak sama dengan hash block $upper' : ''}',
      excludeSemantics: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.cardGap),
          child: Material(
            color: sc?.bg ?? c.surfaceVariant,
            shape: StadiumBorder(side: BorderSide(color: sc?.fg ?? c.muted)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 20, color: sc?.fg ?? c.onBackground),
                    const SizedBox(width: Spacing.s8),
                    Flexible(child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: sc?.fg ?? c.onBackground))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
