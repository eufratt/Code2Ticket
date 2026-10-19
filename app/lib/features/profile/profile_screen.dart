import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../auth/auth_controller.dart';
import 'profile_controller.dart';
import 'user_avatar.dart';

String badgeLabel(String code) => switch (code) {
      'first_ticket' => 'First Ticket',
      'ten_tickets' => '10 Tickets',
      'first_maze_clear' => 'First Maze Clear',
      'maze_master' => 'Maze Master',
      'early_bird' => 'Early Bird',
      _ => code,
    };

/// Memilih gambar dari kamera/galeri; bisa diganti di tes.
typedef PhotoPicker = Future<Uint8List?> Function(ImageSource source);

Future<Uint8List?> _defaultPicker(ImageSource source) async {
  // Batas awal dari pemilih (sisi 1600 px) hanya untuk menghemat memori; pengecilan akhir (512 px, <= 150 KB) di klien.
  final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
  return f?.readAsBytes();
}

/// S-PROF: foto, nama, identitas, level/XP/lencana, dan pintasan Konverter, Saran & Kesan, Pengaturan, Keluar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.picker = _defaultPicker, this.compress});
  final PhotoPicker picker;

  /// Hanya untuk tes: pengganti kompresi di isolate.
  final Future<Uint8List> Function(Uint8List)? compress;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _profile =
      ProfileController(context.read<AuthedApi>(), context.read<AuthController>(), compress: widget.compress);

  @override
  void dispose() {
    _profile.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _changePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('photo_camera'),
            leading: const Icon(Icons.photo_camera),
            title: const Text('Ambil foto (kamera)'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            key: const Key('photo_gallery'),
            leading: const Icon(Icons.photo_library),
            title: const Text('Pilih dari galeri'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    Uint8List? bytes;
    try {
      bytes = await widget.picker(source);
    } catch (_) {
      if (mounted) _toast('Tidak bisa membuka ${source == ImageSource.camera ? 'kamera' : 'galeri'}. Periksa izin aplikasi.');
      return;
    }
    if (bytes == null || !mounted) return; // dibatalkan
    final err = await _profile.uploadPhoto(bytes);
    if (mounted) _toast(err ?? 'Foto profil diperbarui.');
  }

  Future<void> _editName() async {
    final auth = context.read<AuthController>();
    final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(initial: auth.user?.fullName ?? ''));
    if (name == null || !mounted) return;
    final err = await _profile.updateName(name);
    if (mounted) _toast(err ?? 'Nama diperbarui.');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final u = auth.user;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
          children: [
            Center(
              child: Stack(children: [
                InkWell(
                  key: const Key('avatar_button'),
                  customBorder: const CircleBorder(),
                  onTap: _profile.saving ? null : _changePhoto,
                  child: UserAvatar(user: u, radius: 48),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: theme.colorScheme.primary,
                    child: _profile.saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.photo_camera, size: 16, color: theme.colorScheme.onPrimary),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(u?.fullName ?? '-', key: const Key('profile_name'), style: theme.textTheme.titleLarge, textAlign: TextAlign.center)),
              IconButton(key: const Key('edit_name'), tooltip: 'Ubah nama', icon: const Icon(Icons.edit, size: 18), onPressed: _profile.saving ? null : _editName),
            ]),
            Center(child: Text('@${u?.username ?? '-'}')),
            Center(child: Text(u?.email ?? '-', style: theme.textTheme.bodySmall)),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
              Chip(label: Text(u?.role ?? '-')),
              Chip(label: Text('Level ${u?.level ?? 1}')),
              Chip(label: Text('${u?.xp ?? 0} XP')),
            ]),
            if (u != null && u.badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(child: Text('Lencana', style: theme.textTheme.titleSmall)),
              Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                for (final b in u.badges) Chip(avatar: const Icon(Icons.military_tech, size: 18), label: Text(badgeLabel(b))),
              ]),
            ],
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                ListTile(key: const Key('open_converter'), leading: const Icon(Icons.currency_exchange), title: const Text('Konverter'), subtitle: const Text('Mata uang dan waktu'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/converter')),
                ListTile(key: const Key('open_feedback'), leading: const Icon(Icons.rate_review_outlined), title: const Text('Saran & Kesan'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/feedback')),
                ListTile(key: const Key('open_settings'), leading: const Icon(Icons.settings_outlined), title: const Text('Pengaturan'), subtitle: const Text('Mata uang, zona waktu, biometric'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings')),
              ]),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: auth.logout, child: const Text('Keluar')),
          ],
        ),
      ),
    );
  }
}

/// Dialog ubah nama. Controller dimiliki dialog sendiri supaya tidak dibuang saat animasi tutup masih berjalan.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ubah nama'),
        content: TextField(
          key: const Key('name_field'),
          controller: _ctrl,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nama lengkap'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('save_name'), onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Simpan')),
        ],
      );
}
