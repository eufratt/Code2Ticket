import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/geocoding/geocoder.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/inline_message.dart';

/// Dialog lokasi manual: cari nama tempat (Nominatim) lalu pilih satu hasil. Pencarian hanya saat tombol
/// Cari / Enter ditekan (bukan tiap ketikan), minimal 3 huruf.
Future<Place?> showManualLocationDialog(BuildContext context) =>
    showDialog<Place>(context: context, builder: (_) => const _ManualLocationDialog());

class _ManualLocationDialog extends StatefulWidget {
  const _ManualLocationDialog();
  @override
  State<_ManualLocationDialog> createState() => _ManualLocationDialogState();
}

class _ManualLocationDialogState extends State<_ManualLocationDialog> {
  final _text = TextEditingController();
  List<Place>? _results;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    final q = _text.text.trim();
    if (q.length < Geocoder.minQueryLength) {
      setState(() => _error = 'Ketik minimal ${Geocoder.minQueryLength} huruf nama tempat.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<Geocoder>().search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _error = r.isEmpty ? 'Tempat tidak ditemukan. Coba nama kota atau alamat lain.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cari tempat'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('place_field'),
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nama kota, kampus, atau alamat',
                suffixIcon: IconButton(
                  key: const Key('place_search'),
                  tooltip: 'Cari',
                  icon: const Icon(Icons.search),
                  onPressed: _busy ? null : _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: Spacing.s12), child: LinearProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.s12),
                child: InlineMessage(_error!),
              ),
            if (_results != null && _results!.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in _results!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.s8),
            Text('Hasil pencarian: © OpenStreetMap contributors', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal'))],
    );
  }
}
