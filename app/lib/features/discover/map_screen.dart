import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_card.dart';
import '../giveaways/giveaway_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'discover_controller.dart';

/// Id paket untuk User-Agent tile OpenStreetMap (kebijakan tile OSM: identifikasi aplikasi).
const osmUserAgentPackage = 'com.code2ticket.app';
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// S-MAP: peta OpenStreetMap berisi penanda giveaway dari hasil Discover saat ini (kata kunci, filter,
/// Terdekat ikut berlaku). Ketuk penanda -> kartu ringkas -> Detail. Tile dimuat sesuai area yang dilihat
/// (tanpa unduhan massal); atribusi "© OpenStreetMap contributors" selalu terlihat.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.tileProvider});

  /// Hanya untuk tes (tanpa jaringan). null = pemuat tile jaringan bawaan.
  final TileProvider? tileProvider;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  String? _selectedId;
  final _map = MapController();
  bool _fitted = false;

  /// Posisi dan masalah lokasi milik layar Peta saja (tidak mengubah mode Terdekat di Discover).
  LatLng? _here;
  LocationStatus? _problem;
  bool _locating = false;

  /// Dialog izin sistem diminta otomatis paling banyak sekali per pembukaan layar.
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final c = context.read<DiscoverController>();
    Future.microtask(c.ensureLoaded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _asked) return;
      _asked = true;
      _locate(prompt: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _map.dispose();
    super.dispose();
  }

  /// Kembali dari pengaturan sistem: perbarui status tanpa dialog izin.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _problem != null) _locate(prompt: false);
  }

  Future<void> _locate({required bool prompt}) async {
    final service = context.read<LocationService?>();
    if (service == null || _locating) return;
    setState(() => _locating = true);
    final fix = await service.locate(prompt: prompt);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _problem = fix.ok ? null : fix.status;
      if (fix.ok) _here = LatLng(fix.lat!, fix.lng!);
    });
    if (fix.ok && _fitted) _map.move(_here!, 14);
  }

  void _onBannerAction() {
    final p = _problem!;
    if (p == LocationStatus.deniedForever || p == LocationStatus.serviceOff) {
      context.read<LocationService?>()?.openSettingsFor(p);
    } else {
      _locate(prompt: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DiscoverController>();
    final placed = c.items.where((g) => g.hasCoordinates).toList();
    final selected = placed.where((g) => g.id == _selectedId).firstOrNull;
    final me = _here ?? (c.position == null ? null : LatLng(c.position!.lat, c.position!.lng));
    final points = [for (final g in placed) LatLng(g.latitude!, g.longitude!), ?me];

    // Kamera disesuaikan sekali, saat penanda pertama kali ada. Ganti filter sesudahnya tidak menggeser peta.
    if (!_fitted && points.isNotEmpty) {
      _fitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (points.length >= 2) {
          _map.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 14));
        } else {
          _map.move(points.first, 13);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Peta')),
      body: Column(
        children: [
          if (c.offline) OfflineBanner(cachedAt: c.cachedAt),
          if (_problem != null) _MapLocationBanner(status: _problem!, onAction: _onBannerAction),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(-2.5, 118.0),
                    initialZoom: 4.5,
                    onTap: (_, _) => setState(() => _selectedId = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: osmTileUrl,
                      userAgentPackageName: osmUserAgentPackage,
                      tileProvider: widget.tileProvider,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final g in placed)
                          Marker(
                            point: LatLng(g.latitude!, g.longitude!),
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              key: Key('marker_${g.id}'),
                              onTap: () => setState(() => _selectedId = g.id),
                              child: Semantics(
                                button: true,
                                label: 'Giveaway ${g.title}',
                                child: Icon(
                                  Icons.location_on,
                                  size: 44,
                                  color: g.id == _selectedId ? context.colors.accent : context.colors.primary,
                                  shadows: const [Shadow(color: Overlays.markerShadow, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                        if (me != null)
                          Marker(
                            point: me,
                            width: 22,
                            height: 22,
                            child: DecoratedBox(
                              key: const Key('my_position'),
                              decoration: BoxDecoration(
                                color: context.colors.success,
                                shape: BoxShape.circle,
                                border: Border.all(color: context.colors.surface, width: 3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: Spacing.s8,
                  left: Spacing.s8,
                  right: 72,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(Radii.full),
                        boxShadow: AppShadows.card(context.colors),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Spacing.s12, vertical: Spacing.s8),
                        child: Text(
                          key: const Key('map_summary'),
                          _summary(c, placed.length),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.onBackground),
                        ),
                      ),
                    ),
                  ),
                ),
                // Tombol "lokasi saya": menengahkan peta ke posisi bila sudah diketahui; bila belum, meminta posisi
                // lewat mode Terdekat yang sama dengan chip di Discover.
                Positioned(
                  top: Spacing.s8,
                  right: Spacing.s8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.card(context.colors),
                    ),
                    child: IconButton(
                      key: const Key('my_location'),
                      tooltip: 'Lokasi saya',
                      icon: c.locating || _locating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      onPressed: c.locating || _locating ? null : () => me != null ? _map.move(me, 14) : _locate(prompt: true),
                    ),
                  ),
                ),
                const Positioned(right: 0, bottom: 0, child: OsmAttribution()),
                if (selected != null)
                  Positioned(
                    left: Spacing.screen,
                    right: Spacing.screen,
                    bottom: Spacing.s24 + 4,
                    child: _SelectedCard(giveaway: selected),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _summary(DiscoverController c, int placed) {
    if (c.state == LoadState.loading && c.items.isEmpty) return 'Memuat giveaway...';
    if (c.items.isEmpty) return 'Tidak ada giveaway untuk filter ini';
    final missing = c.items.length - placed;
    return missing == 0
        ? '$placed giveaway di peta'
        : '$placed giveaway di peta ($missing tanpa lokasi)';
  }
}

/// Alasan posisi tidak tersedia di Peta + satu tombol aksi (izinkan / buka pengaturan). Peta tetap tampil di bawahnya.
class _MapLocationBanner extends StatelessWidget {
  const _MapLocationBanner({required this.status, required this.onAction});
  final LocationStatus status;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final sc = context.colors.statusWarning;
    return Container(
      key: const Key('map_location_banner'),
      width: double.infinity,
      color: sc.bg,
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locationStatusMessage(status), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: sc.fg)),
          TextButton(
            key: const Key('map_location_action'),
            style: TextButton.styleFrom(minimumSize: const Size(kMinTap, kMinTap)),
            onPressed: onAction,
            child: Text(locationActionLabel(status)),
          ),
        ],
      ),
    );
  }
}

/// Atribusi wajib OpenStreetMap.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});
  @override
  Widget build(BuildContext context) => Container(
        color: context.colors.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '© OpenStreetMap contributors',
          key: const Key('osm_attribution'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.onBackground),
        ),
      );
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.giveaway});
  final Giveaway giveaway;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GiveawayCard(
          key: const Key('selected_card'),
          giveaway: giveaway,
          variant: GiveawayCardVariant.compact,
          onTap: () => context.push('/giveaway/${giveaway.id}', extra: giveaway),
        ),
        const SizedBox(height: Spacing.s8),
        PrimaryButton(
          key: const Key('open_detail'),
          label: 'Lihat detail',
          onPressed: () => context.push('/giveaway/${giveaway.id}', extra: giveaway),
        ),
      ],
    );
  }
}
