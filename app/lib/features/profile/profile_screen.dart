import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
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

/// Semua lencana yang dikenal (yang belum diraih tampil abu-abu, terkunci).
const knownBadges = ['first_ticket', 'ten_tickets', 'first_maze_clear', 'maze_master', 'early_bird'];

/// XP per level: kolom users.level = xp / 500 + 1 (backend/db/01_schema.sql).
const xpPerLevel = 500;

/// Memilih gambar dari kamera/galeri; bisa diganti di tes.
typedef PhotoPicker = Future<Uint8List?> Function(ImageSource source);

Future<Uint8List?> _defaultPicker(ImageSource source) async {
  // Batas awal dari pemilih (sisi 1600 px) hanya untuk menghemat memori; pengecilan akhir (512 px, <= 150 KB) di klien.
  final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
  return f?.readAsBytes();
}

/// S-PROF (tab Profil): foto, nama, identitas, level/XP/lencana, Pengaturan, dan Admin (hanya admin).
/// Saran & Kesan dan Logout ada di bottom navigation; Konverter dan Game di menu fitur Home.
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
    final c = context.colors;
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.listBottom),
          children: [
            Center(
              child: Semantics(
                button: true,
                label: 'Ubah foto profil',
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
                      radius: 16,
                      backgroundColor: c.primary,
                      child: _profile.saving
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.onPrimary))
                          : Icon(Icons.photo_camera, size: 16, color: c.onPrimary),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Spacing.s12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 48), // penyeimbang pensil: teks nama tepat di tengah
              Flexible(child: Text(u?.fullName ?? '-', key: const Key('profile_name'), style: theme.textTheme.titleLarge, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(key: const Key('edit_name'), tooltip: 'Ubah nama', icon: const Icon(Icons.edit, size: 18), onPressed: _profile.saving ? null : _editName),
            ]),
            Center(child: Text('@${u?.username ?? '-'}', style: theme.textTheme.bodyMedium)),
            Center(child: Text(u == null || u.email.isEmpty ? '-' : u.email, style: theme.textTheme.bodySmall?.copyWith(color: c.muted))),
            const SizedBox(height: Spacing.s12),
            Center(child: StatusChip.custom(label: u == null ? '-' : (u.isAdmin ? 'Admin' : 'Pengguna'), tone: u?.isAdmin == true ? StatusTone.info : StatusTone.neutral, icon: Icons.person_outline)),
            const SizedBox(height: Spacing.s16),
            if (u != null) _LevelCard(level: u.level, xp: u.xp),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Lencana'),
            _BadgeGrid(earned: u?.badges ?? const []),
            const SizedBox(height: Spacing.sectionGap),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                if (u?.isAdmin == true) ...[
                  ListTile(key: const Key('open_admin'), leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text('Admin'), subtitle: const Text('Buat giveaway, kode, dan draw'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/admin')),
                  const Divider(indent: Spacing.s16, endIndent: Spacing.s16),
                ],
                ListTile(key: const Key('open_settings'), leading: const Icon(Icons.settings_outlined), title: const Text('Pengaturan'), subtitle: const Text('Mata uang, zona waktu, biometric'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings')),
                if (context.watch<SettingsController?>() case final s?) ...[
                  const Divider(indent: Spacing.s16, endIndent: Spacing.s16),
                  ListTile(key: const Key('open_theme'), leading: Icon(_themeOptions[s.themeMode]!.$2), title: const Text('Tema'), subtitle: Text(_themeOptions[s.themeMode]!.$1), trailing: const Icon(Icons.chevron_right), onTap: () => _pickTheme(context, s)),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

const _themeOptions = {
  ThemeMode.system: ('Ikuti sistem', Icons.brightness_auto_outlined),
  ThemeMode.light: ('Terang', Icons.light_mode_outlined),
  ThemeMode.dark: ('Gelap', Icons.dark_mode_outlined),
};

/// Dialog pilihan tema; berlaku langsung dan dialog menutup setelah memilih.
Future<void> _pickTheme(BuildContext context, SettingsController s) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tema'),
        contentPadding: const EdgeInsets.symmetric(vertical: Spacing.s8),
        content: RadioGroup<ThemeMode>(
          groupValue: s.themeMode,
          onChanged: (v) {
            if (v != null) s.setThemeMode(v);
            Navigator.pop(ctx);
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in _themeOptions.entries)
              RadioListTile<ThemeMode>(key: Key('theme_${e.key.name}'), value: e.key, secondary: Icon(e.value.$2), title: Text(e.value.$1)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal'))],
      ),
    );

/// Lingkaran level + bar XP menuju level berikutnya.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.xp});
  final int level, xp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final inLevel = xp % xpPerLevel;
    return SurfaceCard(
      child: Row(
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle, border: Border.all(color: c.primary, width: 3)),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Center(child: Text('$level', key: const Key('level_circle'), style: theme.textTheme.displaySmall?.copyWith(color: c.onPrimaryContainer))),
              ),
            ),
          ),
          const SizedBox(width: Spacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Level $level', style: theme.textTheme.titleMedium),
                Text('$xp XP', style: theme.textTheme.bodyMedium),
                const SizedBox(height: Spacing.s8),
                Semantics(
                  label: '$inLevel dari $xpPerLevel XP menuju level ${level + 1}',
                  excludeSemantics: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.full),
                    child: LinearProgressIndicator(
                      key: const Key('xp_bar'),
                      value: inLevel / xpPerLevel,
                      minHeight: 8,
                      backgroundColor: c.surfaceVariant,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.s4),
                Text('$inLevel / $xpPerLevel XP menuju level ${level + 1}', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid lencana: yang sudah diraih berwarna, yang belum abu-abu dengan gembok.
class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.earned});
  final List<String> earned;

  @override
  Widget build(BuildContext context) {
    final all = [...knownBadges, for (final b in earned) if (!knownBadges.contains(b)) b];
    return LayoutBuilder(builder: (context, box) {
      const cols = 3;
      final w = (box.maxWidth - Spacing.s12 * (cols - 1)) / cols;
      return Wrap(
        spacing: Spacing.s12,
        runSpacing: Spacing.s12,
        children: [for (final b in all) SizedBox(width: w, child: _BadgeTile(code: b, earned: earned.contains(b)))],
      );
    });
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.code, required this.earned});
  final String code;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = badgeLabel(code);
    return Semantics(
      container: true,
      label: '$label, ${earned ? 'sudah diraih' : 'terkunci'}',
      excludeSemantics: true,
      child: SurfaceCard(
        key: Key('badge_$code'),
        padding: const EdgeInsets.symmetric(vertical: Spacing.s12, horizontal: Spacing.s8),
        child: Column(
          children: [
            Stack(alignment: Alignment.bottomRight, children: [
              DecoratedBox(
                decoration: BoxDecoration(color: earned ? c.accent : c.surfaceVariant, shape: BoxShape.circle),
                child: SizedBox(width: 48, height: 48, child: Icon(Icons.military_tech, size: 28, color: earned ? c.onAccent : c.muted)),
              ),
              if (!earned) Icon(Icons.lock, size: 16, color: c.muted),
            ]),
            const SizedBox(height: Spacing.s8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: earned ? c.onBackground : c.muted),
            ),
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
