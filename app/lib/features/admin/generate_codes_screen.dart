import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_models.dart';
import 'admin_controller.dart';

/// Generate Code (POST /admin/giveaways/:id/codes). Hasil hanya ada di memori layar ini: tidak disimpan di SQLite,
/// tidak ditulis ke log, tidak masuk riwayat. Kode dibuang saat layar ditutup.
class GenerateCodesScreen extends StatefulWidget {
  const GenerateCodesScreen({super.key, required this.giveawayId, this.giveaway});
  final String giveawayId;
  final Giveaway? giveaway;

  @override
  State<GenerateCodesScreen> createState() => _GenerateCodesScreenState();
}

class _GenerateCodesScreenState extends State<GenerateCodesScreen> {
  final _form = GlobalKey<FormState>();
  final _count = TextEditingController(text: '5');
  List<String>? _codes;
  int _requested = 0;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    _codes = null;
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_form.currentState!.validate()) return;
    final n = int.parse(_count.text.trim());
    setState(() => _error = null);
    final r = await context.read<AdminController>().generateCodes(widget.giveawayId, n);
    if (r == null || !mounted) return;
    setState(() {
      if (r.isOk) {
        _codes = r.data!;
        _requested = n;
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AdminController>().busy;
    final theme = Theme.of(context);
    final codes = _codes;
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Code')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          if (widget.giveaway != null) Text(widget.giveaway!.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.s12),
          if (codes == null) ...[
            Form(
              key: _form,
              child: TextFormField(
                key: const Key('code_count'),
                controller: _count,
                decoration: const InputDecoration(labelText: 'Jumlah kode', helperText: '1 sampai 1000'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 1 || n > 1000 ? 'Isi bilangan 1 sampai 1000' : null;
                },
              ),
            ),
            const SizedBox(height: Spacing.s16),
            if (_error != null) ...[InlineMessage(_error!), const SizedBox(height: Spacing.s12)],
            PrimaryButton(key: const Key('generate_codes'), label: 'Buat kode', icon: Icons.vpn_key_outlined, loading: busy, onPressed: _generate),
          ] else ...[
            const InlineMessage(
              'Salin dan bagikan kode sekarang. Kode hanya ditampilkan di layar ini dan tidak disimpan di perangkat; '
              'setelah keluar dari layar ini, lihat lagi lewat Daftar Kode.',
              tone: StatusTone.warning,
            ),
            const SizedBox(height: Spacing.s12),
            if (codes.length < _requested) ...[
              InlineMessage('Hanya ${codes.length} dari $_requested kode yang berhasil dibuat (bentrok acak). Buat lagi untuk sisanya.', tone: StatusTone.info),
              const SizedBox(height: Spacing.s12),
            ],
            SectionHeader('${codes.length} kode dibuat'),
            for (final code in codes)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.s8),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s4),
                  child: Row(children: [
                    Expanded(child: Text(code, style: AppTypography.mono(theme.textTheme.titleMedium!).copyWith(letterSpacing: 1))),
                    IconButton(
                      key: Key('copy_$code'),
                      tooltip: 'Salin kode $code',
                      icon: const Icon(Icons.copy_outlined),
                      color: context.colors.primary,
                      onPressed: () => _copy(code, 'Kode disalin.'),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: Spacing.s8),
            PrimaryButton(key: const Key('copy_all'), label: 'Salin semua', icon: Icons.copy_all_outlined, onPressed: codes.isEmpty ? null : () => _copy(codes.join('\n'), '${codes.length} kode disalin.')),
            const SizedBox(height: Spacing.s12),
            PrimaryButton(key: const Key('generate_again'), label: 'Buat lagi', variant: ButtonVariant.secondary, onPressed: () => setState(() => _codes = null)),
          ],
        ],
      ),
    );
  }
}
