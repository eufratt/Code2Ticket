import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/display.dart';
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
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Saran & Kesan')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Untuk mata kuliah Pemrograman Aplikasi Mobile', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              key: const Key('suggestion_field'),
              controller: _suggestion,
              enabled: !_c.sending,
              maxLines: 4,
              maxLength: feedbackMaxLength,
              decoration: const InputDecoration(labelText: 'Saran', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('impression_field'),
              controller: _impression,
              enabled: !_c.sending,
              maxLines: 4,
              maxLength: feedbackMaxLength,
              decoration: const InputDecoration(labelText: 'Kesan', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, key: const Key('feedback_error'), style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_success!, key: const Key('feedback_success'), style: TextStyle(color: theme.colorScheme.primary)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('send_feedback'),
              onPressed: _c.sending ? null : _send,
              child: _c.sending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Kirim'),
            ),
            const Divider(height: 40),
            Text('Riwayat kirimanmu', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_c.loadingHistory && _c.history.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_c.historyError != null && _c.history.isEmpty)
              Column(children: [
                Text(_c.historyError!, key: const Key('history_error')),
                TextButton(onPressed: _c.loadHistory, child: const Text('Coba lagi')),
              ])
            else if (_c.history.isEmpty)
              const Text('Belum ada kiriman.', key: Key('history_empty'))
            else
              for (final e in _c.history)
                Card(
                  key: Key('feedback_${e.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (e.createdAt != null) Text(context.when(e.createdAt!), style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text('Saran', style: theme.textTheme.labelMedium),
                      Text(e.suggestion),
                      const SizedBox(height: 6),
                      Text('Kesan', style: theme.textTheme.labelMedium),
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
