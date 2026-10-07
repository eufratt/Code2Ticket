import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../controllers/input_code_controller.dart';
import '../controllers/input_code_state.dart';
import '../widgets/code_input_formatter.dart';
import '../widgets/ticket_result_card.dart';

class InputCodeScreen extends ConsumerStatefulWidget {
  const InputCodeScreen({super.key});

  @override
  ConsumerState<InputCodeScreen> createState() => _InputCodeScreenState();
}

class _InputCodeScreenState extends ConsumerState<InputCodeScreen> {
  final _codeController = TextEditingController();
  UserLocation? _currentLocation;

  @override
  void initState() {
    super.initState();
    _checkInitialLocation();
  }

  Future<void> _checkInitialLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final loc = await locationService.getCurrentLocation(requestIfDenied: false);
    if (mounted) {
      setState(() {
        _currentLocation = loc;
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleValidate() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap masukkan kode partisipasi terlebih dahulu'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    final locationService = ref.read(locationServiceProvider);

    // Request GPS location for geo-restricted validation
    UserLocation loc = _currentLocation ??
        await locationService.getCurrentLocation(requestIfDenied: true);

    if (loc.status != LocationPermissionStatus.granted) {
      loc = await locationService.getCurrentLocation(requestIfDenied: true);
    }

    if (mounted) {
      setState(() {
        _currentLocation = loc;
      });
    }

    final double? lat =
        loc.status == LocationPermissionStatus.granted ? loc.latitude : null;
    final double? lng =
        loc.status == LocationPermissionStatus.granted ? loc.longitude : null;

    await ref.read(inputCodeControllerProvider.notifier).redeemCode(
          code,
          latitude: lat,
          longitude: lng,
        );
  }

  void _handleRedeemAnother() {
    _codeController.clear();
    ref.read(inputCodeControllerProvider.notifier).reset();
  }

  void _handleViewMyTickets() {
    ref.read(inputCodeControllerProvider.notifier).reset();
    context.go('/tickets');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inputCodeControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Input Kode Partisipasi'),
        actions: [
          if (state is InputCodeSuccess)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Tukarkan Kode Baru',
              onPressed: _handleRedeemAnother,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: switch (state) {
              InputCodeSuccess(:final result) when result.ticket != null =>
                TicketResultCard(
                  key: const ValueKey('success_card'),
                  ticket: result.ticket!,
                  onRedeemAnother: _handleRedeemAnother,
                  onViewMyTickets: _handleViewMyTickets,
                ),
              _ => _buildInputForm(context, state, isDark),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputForm(
    BuildContext context,
    InputCodeState state,
    bool isDark,
  ) {
    final isLoading = state is InputCodeLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Decorative Hero Icon / Header
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.ticketGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryPurple.withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Tukarkan Kode Undian',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 8),

        Text(
          'Masukkan kode partisipasi dari struk belanja, tiket acara, atau merchant partner untuk mendapatkan nomor tiket undian resmi.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            height: 1.4,
          ),
        ),

        const SizedBox(height: 28),

        // Error Banner (if any)
        if (state is InputCodeError) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.errorRed.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.errorRed.withAlpha(120),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.errorRed,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gagal Menukarkan Kode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.errorRed,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.message,
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.errorRed,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ref.read(inputCodeControllerProvider.notifier).clearError();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Input Field with auto-uppercase & auto-dash formatter
        AppTextField(
          controller: _codeController,
          label: 'Kode Partisipasi',
          hintText: 'Misal: GAME-PKW-001',
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [CodeInputFormatter()],
          prefixIcon: const Icon(
            Icons.qr_code_rounded,
            color: AppColors.primaryPurple,
          ),
          suffixIcon: _codeController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () {
                    setState(() {
                      _codeController.clear();
                    });
                    ref.read(inputCodeControllerProvider.notifier).clearError();
                  },
                )
              : null,
          onChanged: (_) {
            setState(() {});
          },
        ),

        const SizedBox(height: 14),

        // Geo-location / GPS Verification Status Card
        _buildLocationStatusCard(isDark),

        const SizedBox(height: 28),

        // Validate Button
        AppButton(
          text: isLoading ? 'Memvalidasi Kode & Lokasi...' : 'Validasi & Klaim Tiket',
          icon: Icons.check_circle_outline_rounded,
          isLoading: isLoading,
          onPressed: isLoading ? null : _handleValidate,
        ),
      ],
    );
  }

  Widget _buildLocationStatusCard(bool isDark) {
    final loc = _currentLocation;
    final isGranted = loc?.status == LocationPermissionStatus.granted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isGranted
            ? AppColors.successGreen.withValues(alpha: 0.08)
            : isDark
                ? AppColors.darkCard
                : AppColors.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? AppColors.successGreen.withValues(alpha: 0.3)
              : Colors.grey.withAlpha(50),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isGranted ? Icons.location_on_rounded : Icons.my_location_rounded,
            size: 20,
            color: isGranted ? AppColors.successGreen : AppColors.accentCyan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGranted
                      ? 'GPS Aktif (${loc!.latitude.toStringAsFixed(3)}, ${loc.longitude.toStringAsFixed(3)})'
                      : 'Verifikasi Lokasi (LBS)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isGranted ? AppColors.successGreen : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isGranted
                      ? 'Koordinat GPS Anda siap diverifikasi untuk undian berbasis radius wilayah.'
                      : 'Izin GPS akan diverifikasi jika kode berasal dari campaign berbasis lokasi.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!isGranted)
            TextButton(
              onPressed: () async {
                final locationService = ref.read(locationServiceProvider);
                final updated = await locationService.getCurrentLocation(requestIfDenied: true);
                if (mounted) setState(() => _currentLocation = updated);
              },
              child: const Text('Cek GPS', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
