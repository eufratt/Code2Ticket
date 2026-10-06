import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/discover_filter_model.dart';

class DiscoverFilterModal extends StatefulWidget {
  final DiscoverFilterModel initialFilter;
  final ValueChanged<DiscoverFilterModel> onApply;

  const DiscoverFilterModal({
    super.key,
    required this.initialFilter,
    required this.onApply,
  });

  @override
  State<DiscoverFilterModal> createState() => _DiscoverFilterModalState();
}

class _DiscoverFilterModalState extends State<DiscoverFilterModal> {
  late String _selectedCategory;
  late DiscoverSort _selectedSort;
  bool? _onlyGeoRestricted;
  double? _maxRadiusKm;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialFilter.category;
    _selectedSort = widget.initialFilter.sort;
    _onlyGeoRestricted = widget.initialFilter.onlyGeoRestricted;
    _maxRadiusKm = widget.initialFilter.maxRadiusKm;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter Undian',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedCategory = 'Semua';
                      _selectedSort = DiscoverSort.deadlineAsc;
                      _onlyGeoRestricted = null;
                      _maxRadiusKm = null;
                    });
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            // 1. Kategori
            const Text(
              'Kategori Campaign',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DiscoverFilterModel.availableCategories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primaryBlue : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedCategory = cat);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 2. Urutkan (Deadline & Hadiah)
            const Text(
              'Urutkan Berdasarkan',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DiscoverSort.values.map((sort) {
                final isSelected = _selectedSort == sort;
                return ChoiceChip(
                  label: Text(sort.label),
                  selected: isSelected,
                  selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primaryPurple : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedSort = sort);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 3. Cakupan Area / Radius
            const Text(
              'Cakupan Wilayah / Radius',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Semua Wilayah'),
                  selected: _onlyGeoRestricted == null,
                  onSelected: (sel) {
                    if (sel) setState(() => _onlyGeoRestricted = null);
                  },
                ),
                ChoiceChip(
                  label: const Text('Hanya Berbasis Lokasi (DIY)'),
                  selected: _onlyGeoRestricted == true,
                  onSelected: (sel) {
                    if (sel) setState(() => _onlyGeoRestricted = true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Hanya Nasional'),
                  selected: _onlyGeoRestricted == false,
                  onSelected: (sel) {
                    if (sel) setState(() => _onlyGeoRestricted = false);
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Apply button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  final newFilter = widget.initialFilter.copyWith(
                    category: _selectedCategory,
                    sort: _selectedSort,
                    onlyGeoRestricted: () => _onlyGeoRestricted,
                    maxRadiusKm: _maxRadiusKm,
                  );
                  widget.onApply(newFilter);
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Terapkan Filter',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
