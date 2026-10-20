import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_card.dart';
import 'assistant_controller.dart';
import 'assistant_models.dart';

const _welcome = 'Halo! Aku Asisten Code2Ticket. Tanya cara kerja aplikasi (kode, tiket, draw, cek keaslian) atau minta aku carikan giveaway yang sedang aktif.';
const _quickQuestions = [
  'Bagaimana cara kerja Code2Ticket?',
  'Ada giveaway gaming apa?',
  'Bagaimana cara cek keaslian hasil draw?',
];

/// Layar Asisten (M7b, dari Home): gelembung chat kiri (asisten) / kanan (pengguna), saran cepat, kartu giveaway dari jawaban,
/// dan kolom input 500 karakter. Riwayat tersimpan di SQLite per pengguna.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<AssistantController>().load();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _canSend(AssistantController c) {
    final n = _input.text.runes.length;
    return !c.sending && _input.text.trim().isNotEmpty && n <= chatMaxLength;
  }

  Future<void> _send(AssistantController c, String text) async {
    if (c.sending) return;
    _input.clear();
    final f = c.send(text);
    _toBottom();
    await f;
    _toBottom();
  }

  /// Daftar dibalik (terbaru di indeks 0), jadi "bawah" = offset 0.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final d = Motion.of(context, Motion.slow);
      d == Duration.zero ? _scroll.jumpTo(0) : _scroll.animateTo(0, duration: d, curve: Motion.curve);
    });
  }

  Future<void> _confirmClear(AssistantController c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus percakapan?'),
        content: const Text('Seluruh riwayat percakapan dengan Asisten di perangkat ini dihapus dan tidak bisa dikembalikan.'),
        actions: [
          PrimaryButton(key: const Key('clear_cancel'), label: 'Batal', variant: ButtonVariant.text, expand: false, onPressed: () => Navigator.pop(ctx, false)),
          PrimaryButton(key: const Key('clear_confirm'), label: 'Hapus', expand: false, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (yes == true) await c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssistantController>(
      builder: (context, c, _) {
        // Terbaru di indeks 0: [mengetik] [pesan terbaru ... terlama] [saran cepat] [sambutan].
        final items = <Widget>[
          if (c.sending) const _TypingBubble(),
          for (final m in c.messages.reversed) _MessageItem(message: m, onRetry: c.canRetry && identical(m, c.messages.last) ? c.retry : null),
          if (c.messages.isEmpty && !c.sending) _QuickQuestions(onPick: (q) => _send(c, q)),
          const _Bubble(role: ChatRole.assistant, text: _welcome, key: Key('welcome')),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Asisten'),
            actions: [
              IconButton(
                key: const Key('clear_chat'),
                tooltip: 'Hapus percakapan',
                icon: const Icon(Icons.delete_outline),
                onPressed: c.messages.isEmpty || c.sending ? null : () => _confirmClear(c),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  key: const Key('chat_list'),
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(Spacing.screen),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Spacing.s12),
                  itemBuilder: (_, i) => items[i],
                ),
              ),
              ListenableBuilder(
                listenable: _input,
                builder: (context, _) => _InputBar(
                  controller: _input,
                  canSend: _canSend(c),
                  sending: c.sending,
                  onSend: () => _send(c, _input.text.trim()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({required this.message, required this.onRetry});
  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.isError) return _ErrorBubble(text: m.text, onRetry: onRetry);
    return Column(
      crossAxisAlignment: m.role == ChatRole.user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _Bubble(role: m.role, text: m.text),
        for (final g in m.related)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.9),
              child: GiveawayCard(
                key: Key('related_${g.id}'),
                giveaway: g,
                variant: GiveawayCardVariant.compact,
                onTap: () => context.push('/giveaway/${g.id}', extra: g),
              ),
            ),
          ),
      ],
    );
  }
}

/// Gelembung teks: pengguna di kanan (primary), asisten di kiri (surface). Lebar maksimum 80% layar.
class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.role, required this.text});
  final ChatRole role;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = role == ChatRole.user;
    const r = Radius.circular(Radii.card), tail = Radius.circular(Spacing.s4);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Semantics(
          label: mine ? 'Kamu: $text' : 'Asisten: $text',
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mine ? c.primary : c.surface,
              border: mine ? null : Border.all(color: c.outline),
              borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? r : tail, bottomRight: mine ? tail : r),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.s12, vertical: Spacing.s8 + 2),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mine ? c.onPrimary : c.onBackground)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.text, required this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.9),
            child: InlineMessage(text, key: const Key('chat_error')),
          ),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s4),
              child: PrimaryButton(key: const Key('retry_chat'), label: 'Kirim ulang', icon: Icons.refresh, variant: ButtonVariant.text, expand: false, onPressed: onRetry),
            ),
        ],
      );
}

class _QuickQuestions extends StatelessWidget {
  const _QuickQuestions({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Spacing.s8,
        runSpacing: Spacing.s8,
        children: [
          for (final q in _quickQuestions) ActionChip(key: Key('quick_$q'), label: Text(q), onPressed: () => onPick(q)),
        ],
      );
}

/// Indikator mengetik: tiga titik berdenyut bergantian; statis bila animasi dikurangi.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Kecerahan titik ke-[i]: naik lalu turun bergantian dalam satu putaran.
  double _opacity(int i) {
    if (Motion.reduced(context)) return 0.6;
    final t = (_anim.value * 3 - i) % 3;
    return 0.3 + 0.7 * (t < 1 ? t : (t < 2 ? 2 - t : 0));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const r = Radius.circular(Radii.card);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        key: const Key('typing'),
        label: 'Asisten sedang mengetik',
        liveRegion: true,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.outline),
                borderRadius: const BorderRadius.only(topLeft: r, topRight: r, bottomRight: r, bottomLeft: Radius.circular(Spacing.s4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s12),
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : Spacing.s4),
                          child: Opacity(
                            opacity: _opacity(i),
                            child: DecoratedBox(decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle), child: const SizedBox(width: 8, height: 8)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const WakingUpNotice(),
          ],
        ),
      ),
    );
  }
}

/// Kolom input + tombol kirim. Penghitung memakai jumlah code point (sama dengan validasi server), bukan huruf.
class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.canSend, required this.sending, required this.onSend});
  final TextEditingController controller;
  final bool canSend, sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = controller.text.runes.length;
    final over = n > chatMaxLength;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.outline))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.s8, Spacing.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat_field'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Tulis pertanyaanmu',
                  counterText: over ? '$n/$chatMaxLength · terlalu panjang' : '$n/$chatMaxLength',
                  counterStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: over ? c.error : c.muted),
                ),
              ),
            ),
            const SizedBox(width: Spacing.s4),
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s4),
              child: IconButton.filled(
                key: const Key('send_chat'),
                tooltip: 'Kirim',
                constraints: const BoxConstraints(minWidth: kMinTap, minHeight: kMinTap),
                onPressed: canSend ? onSend : null,
                icon: sending
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.muted))
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
