import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/map_controller.dart';
import '../widgets/giveaway_marker_popup.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final MapController _mapController;
  final TextEditingController _searchController = TextEditingController();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _moveToLocation(double lat, double lng, {double zoom = 14.0}) {
    _mapController.move(LatLng(lat, lng), zoom);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapControllerProvider);
    final userLoc = state.userLocation;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final initialCenter = LatLng(userLoc.latitude, userLoc.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Giveaway & Radius'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Segarkan Lokasi',
            onPressed: () async {
              await ref.read(mapControllerProvider.notifier).refreshLocation();
              final updated = ref.read(mapControllerProvider).userLocation;
              _moveToLocation(updated.latitude, updated.longitude);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. FlutterMap with OSM Tiles
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 13.0,
              onTap: (_, _) {
                ref.read(mapControllerProvider.notifier).selectGiveaway(null);
                setState(() => _showSuggestions = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.code2ticket',
              ),

              // Radius Circles for Geo-restricted campaigns
              CircleLayer(
                circles: state.filteredGiveaways
                    .where((g) => g.isGeoRestricted && g.latitude != null && g.longitude != null)
                    .map((g) {
                  final radiusMeters = (g.radiusKm ?? 10.0) * 1000.0;
                  final isSelected = state.selectedGiveaway?.id == g.id;
                  return CircleMarker(
                    point: LatLng(g.latitude!, g.longitude!),
                    radius: radiusMeters,
                    useRadiusInMeter: true,
                    color: isSelected
                        ? AppColors.primaryPurple.withValues(alpha: 0.22)
                        : AppColors.primaryBlue.withValues(alpha: 0.12),
                    borderColor: isSelected
                        ? AppColors.primaryPurple
                        : AppColors.primaryBlue.withValues(alpha: 0.4),
                    borderStrokeWidth: isSelected ? 2.5 : 1.5,
                  );
                }).toList(),
              ),

              // Markers Layer: User location + Giveaway pins
              MarkerLayer(
                markers: [
                  // User Location Pin
                  Marker(
                    point: LatLng(userLoc.latitude, userLoc.longitude),
                    width: 50,
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryBlue,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Giveaway Pins
                  ...state.filteredGiveaways
                      .where((g) => g.latitude != null && g.longitude != null)
                      .map((g) {
                    final isSelected = state.selectedGiveaway?.id == g.id;
                    return Marker(
                      point: LatLng(g.latitude!, g.longitude!),
                      width: isSelected ? 52 : 44,
                      height: isSelected ? 52 : 44,
                      child: GestureDetector(
                        onTap: () {
                          ref.read(mapControllerProvider.notifier).selectGiveaway(g);
                          _moveToLocation(g.latitude!, g.longitude!, zoom: 14.5);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryPurple : AppColors.ticketGold,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: (isSelected ? AppColors.primaryPurple : AppColors.ticketGold)
                                    .withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            isSelected ? Icons.place : Icons.card_giftcard,
                            color: Colors.white,
                            size: isSelected ? 26 : 22,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),

              // OSM Attribution according to TOS
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // 2. Top Bar: Search Bar & Radius Filter Chips
          PositionSafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nominatim Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        ref.read(mapControllerProvider.notifier).onSearchQueryChanged(val);
                        setState(() => _showSuggestions = val.isNotEmpty);
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari tempat / alamat di peta...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: state.isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref.read(mapControllerProvider.notifier).clearSearch();
                                      setState(() => _showSuggestions = false);
                                    },
                                  )
                                : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  // Search Suggestions Dropdown
                  if (_showSuggestions && state.searchSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: state.searchSuggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place = state.searchSuggestions[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined, size: 20),
                            title: Text(
                              place.shortTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: Text(
                              place.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () {
                              _moveToLocation(place.latitude, place.longitude, zoom: 15.0);
                              ref.read(mapControllerProvider.notifier).updateUserLocation(
                                    LatLng(place.latitude, place.longitude),
                                  );
                              setState(() => _showSuggestions = false);
                              FocusScope.of(context).unfocus();
                            },
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Radius Filter Chips
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildRadiusChip('Semua Radius', null, state.selectedRadiusKm),
                        const SizedBox(width: 8),
                        _buildRadiusChip('≤ 5 km', 5.0, state.selectedRadiusKm),
                        const SizedBox(width: 8),
                        _buildRadiusChip('≤ 10 km', 10.0, state.selectedRadiusKm),
                        const SizedBox(width: 8),
                        _buildRadiusChip('≤ 15 km', 15.0, state.selectedRadiusKm),
                        const SizedBox(width: 8),
                        _buildRadiusChip('≤ 25 km', 25.0, state.selectedRadiusKm),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Recenter & GPS Info Action Button
          Positioned(
            right: 16,
            bottom: state.selectedGiveaway != null ? 240 : 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'my_location_btn',
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  tooltip: 'Pusatkan ke Lokasi Saya',
                  onPressed: () {
                    _moveToLocation(userLoc.latitude, userLoc.longitude, zoom: 14.0);
                  },
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // 4. Selected Giveaway Preview Bottom Card
          if (state.selectedGiveaway != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GiveawayMarkerPopup(
                giveaway: state.selectedGiveaway!,
                onClose: () {
                  ref.read(mapControllerProvider.notifier).selectGiveaway(null);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRadiusChip(String label, double? radius, double? currentSelected) {
    final isSelected = radius == currentSelected;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.primaryPurple : null,
      ),
      onSelected: (_) {
        ref.read(mapControllerProvider.notifier).setRadiusFilter(radius);
      },
    );
  }
}

class PositionSafeArea extends StatelessWidget {
  final Widget child;
  const PositionSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(child: child),
    );
  }
}
