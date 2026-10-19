import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/display.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'feedback_controller.dart';

/// S-FEEDBACK: Saran & Kesan untuk mata kuliah Pemrograman Aplikasi Mobile + riwayat kiriman sendiri.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final FeedbackController _c = FeedbackController(context.read<AuthedApi>());
  final _suggestion = TextEditingController();
  final _impression = TextEditingController();
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    Future.microtask(_c.loadHistory);
  }

  @override
  void dispose() {
    _c.dispose();
    _suggestion.dispose();
    _impression.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _error = null;
      _success = null;
    });
    final err = await _c.submit(_suggestion.text, _impression.text);
    if (!mounted) return;
    setState(() {
      _error = err;
      if (err == null) {
        _success = 'Terima kasih! Saran & kesanmu terkirim.';
        _suggestion.clear();
        _impression.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Saran & Kesan')),
        body: ListView(
          padding: const EdgeInsets.all(Spacing.screen),
          children: [
            Text('Untuk mata kuliah Pemrograman Aplikasi Mobile', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
            const SizedBox(height: Spacing.s12),
            TextField(
              key: const Key('suggestion_field'),
              controller: _suggestion,
              enabled: !_c.sending,
              maxLines: 4,
              maxLength: feedbackMaxLength,
              decoration: const InputDecoration(labelText: 'Saran', alignLabelWithHint: true),
            ),
            const SizedBox(height: Spacing.s12),
            TextField(
              key: const Key('impression_field'),
              controller: _impression,
              enabled: !_c.sending,
              maxLines: 4,
              maxLength: feedbackMaxLength,
              decoration: const InputDecoration(labelText: 'Kesan', alignLabelWithHint: true),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s4),
                child: InlineMessage(_error!, key: const Key('feedback_error')),
              ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s4),
                child: InlineMessage(_success!, key: const Key('feedback_success'), tone: StatusTone.success),
              ),
            const SizedBox(height: Spacing.s16),
            PrimaryButton(key: const Key('send_feedback'), label: 'Kirim', loading: _c.sending, onPressed: _c.sending ? null : _send),
            if (_c.sending) const WakingUpNotice(),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Riwayat kirimanmu'),
            if (_c.loadingHistory && _c.history.isEmpty)
              const SkeletonLoader(shape: SkeletonShape.ticket, count: 2, shrinkWrap: true, showWakingNotice: false)
            else if (_c.historyError != null && _c.history.isEmpty)
              ErrorState(key: const Key('history_error'), compact: true, message: _c.historyError!, onRetry: _c.loadHistory)
            else if (_c.history.isEmpty)
              const EmptyState(
                key: Key('history_empty'),
                compact: true,
                icon: Icons.rate_review_outlined,
                title: 'Belum ada kiriman.',
                message: 'Saran dan kesan yang kamu kirim akan muncul di sini.',
              )
            else
              for (final e in _c.history)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.cardGap),
                  child: SurfaceCard(
                    key: Key('feedback_${e.id}'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (e.createdAt != null) Text(context.when(e.createdAt!), style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                      const SizedBox(height: Spacing.s8),
                      Text('Saran', style: theme.textTheme.labelMedium?.copyWith(color: c.muted)),
                      Text(e.suggestion),
                      const SizedBox(height: Spacing.s8),
                      Text('Kesan', style: theme.textTheme.labelMedium?.copyWith(color: c.muted)),
                      Text(e.impression),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
