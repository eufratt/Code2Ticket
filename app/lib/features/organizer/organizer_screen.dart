import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/open_link.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'organizer_contact.dart';

const _steps = [
  'Hubungi admin lewat email dan kirim data giveaway.',
  'Admin membuat giveaway dan kode untukmu.',
  'Bagikan kode ke peserta (kamu yang menentukan cara peserta mendapatkannya).',
  'Draw berjalan otomatis pada jadwal dan pemenang tampil di aplikasi.',
];

const _prepare = [
  'Nama dan deskripsi giveaway',
  'Kategori',
  'Nama hadiah dan nilainya (Rp)',
  'Periode (mulai, berakhir)',
  'Jadwal draw',
  'Jumlah pemenang',
  'Batas tiket per peserta',
  'Jumlah kode yang dibutuhkan',
  'Cara mendapatkan kode dan tautan penyelenggara (opsional)',
  'Lokasi dan radius bila tukar kode dibatasi area',
];

/// S-ORG: informasi bagi penyelenggara yang ingin membuat giveaway. Tidak ada peran penyelenggara dan tidak ada pembuatan
/// giveaway mandiri: admin yang membuatnya, penyelenggara menghubungi admin lewat email. Teks panduan tetap tampil
/// tanpa jaringan; hanya tombol yang bergantung pada kontak dari server (simpanan terakhir boleh dipakai).
class OrganizerScreen extends StatefulWidget {
  const OrganizerScreen({super.key});
  @override
  State<OrganizerScreen> createState() => _OrganizerScreenState();
}

class _OrganizerScreenState extends State<OrganizerScreen> {
  @override
  void initState() {
    super.initState();
    final c = context.read<OrganizerContactController?>();
    if (c != null) Future.microtask(c.load);
  }

  Future<void> _mail(BuildContext context, OrganizerContact contact) async {
    final messenger = ScaffoldMessenger.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buka aplikasi email?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kamu akan menulis email ke admin Code2Ticket lewat aplikasi email di perangkatmu.'),
            const SizedBox(height: Spacing.s12),
            Text('Tujuan: ${contact.email}', key: const Key('mail_target'), style: Theme.of(ctx).textTheme.titleSmall),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(key: const Key('confirm_open_mail'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka')),
        ],
      ),
    );
    if (go != true) return;
    var opened = false;
    try {
      opened = await openExternal(organizerMailto(contact.email));
    } catch (_) {}
    if (!opened) messenger.showSnackBar(const SnackBar(content: Text('Tidak bisa membuka aplikasi email.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final ctl = context.watch<OrganizerContactController?>();
    final contact = ctl?.contact;
    final loading = ctl != null && ctl.state != LoadState.loaded;
    return Scaffold(
      appBar: AppBar(title: const Text('Untuk Penyelenggara')),
      body: Column(children: [
        if (context.watch<AuthController?>()?.offlineSession ?? false) const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ctl?.load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s24),
              children: [
                Semantics(header: true, child: Text('Punya giveaway? Jalankan drawnya di Code2Ticket.', style: theme.textTheme.titleLarge)),
                const SizedBox(height: Spacing.s8),
                Text(
                  'Undian berjalan otomatis sesuai jadwal dan hasilnya tercatat di rantai hash yang dapat diperiksa siapa pun.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                ),
                const SizedBox(height: Spacing.sectionGap),
                const SectionHeader('Cara kerjanya'),
                SurfaceCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < _steps.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.s12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 28, child: Text('${i + 1}.', style: theme.textTheme.titleSmall)),
                          Expanded(child: Text(_steps[i], style: theme.textTheme.bodyMedium)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: Spacing.sectionGap),
                const SectionHeader('Data yang perlu kamu siapkan'),
                SurfaceCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < _prepare.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.s8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 20, child: Text('•', style: theme.textTheme.bodyMedium)),
                          Expanded(child: Text(_prepare[i], style: theme.textTheme.bodyMedium)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: Spacing.sectionGap),
                const InlineMessage('Hasil draw tercatat di rantai hash yang dapat diperiksa siapa pun.', tone: StatusTone.info),
                const SizedBox(height: Spacing.sectionGap),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(Spacing.s12), child: CircularProgressIndicator(key: Key('organizer_loading'))))
                else if (contact == null)
                  Text('Kontak admin belum tersedia. Coba lagi nanti.', key: const Key('contact_unavailable'), style: theme.textTheme.bodyMedium?.copyWith(color: c.muted))
                else ...[
                  if (contact.note != null) ...[
                    Text(contact.note!, key: const Key('contact_note'), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Spacing.s12),
                  ],
                  PrimaryButton(
                    key: const Key('contact_admin_email'),
                    label: 'Hubungi admin lewat email',
                    icon: Icons.mail_outline,
                    onPressed: () => _mail(context, contact),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
