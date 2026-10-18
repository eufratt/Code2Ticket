import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../widgets/state_views.dart';
import '../giveaways/giveaway_card.dart';
import '../giveaways/giveaway_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'discover_controller.dart';

/// Id paket untuk User-Agent tile OpenStreetMap (kebijakan tile OSM: identifikasi aplikasi).
const osmUserAgentPackage = 'com.example.code2ticket';
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

class _MapScreenState extends State<MapScreen> {
  String? _selectedId;
  final _map = MapController();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<DiscoverController>();
    Future.microtask(c.ensureLoaded);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DiscoverController>();
    final placed = c.items.where((g) => g.hasCoordinates).toList();
    final selected = placed.where((g) => g.id == _selectedId).firstOrNull;
    final me = c.position == null ? null : LatLng(c.position!.lat, c.position!.lng);
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
                              child: Icon(
                                Icons.location_on,
                                size: 44,
                                color: g.id == _selectedId
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
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
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text(
                        key: const Key('map_summary'),
                        _summary(c, placed.length),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
                const Positioned(right: 0, bottom: 0, child: OsmAttribution()),
                if (selected != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
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

/// Atribusi wajib OpenStreetMap.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: const Text(
          '© OpenStreetMap contributors',
          key: Key('osm_attribution'),
          style: TextStyle(fontSize: 11, color: Colors.black87),
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
          onTap: () => context.push('/giveaway/${giveaway.id}', extra: giveaway),
        ),
        FilledButton.tonal(
          key: const Key('open_detail'),
          onPressed: () => context.push('/giveaway/${giveaway.id}', extra: giveaway),
          child: const Text('Lihat detail'),
        ),
      ],
    );
  }
}
