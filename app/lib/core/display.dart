import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'currency/currency.dart';
import 'currency/rates_controller.dart';
import 'settings/settings_controller.dart';
import 'time/zones.dart';

/// Tampilan uang dan waktu sesuai pilihan pengguna (Pengaturan). Memantau perubahan pilihan dan kurs.
extension DisplayContext on BuildContext {
  /// Nilai hadiah (rupiah di backend) dalam mata uang pilihan. Bila kurs belum ada, ditampilkan dalam IDR.
  String money(int? idr) {
    if (idr == null) return '-';
    return formatPrize(idr, watch<SettingsController>().currency, watch<RatesController>().rates);
  }

  /// Waktu dalam zona pilihan: "19 Okt 2026, 03.29 WIB".
  String when(DateTime t) => formatInZone(t, watch<SettingsController>().zone);
}

/// Keterangan kurs di bawah nilai hadiah: "Kurs per 19 Okt 2026" (+ label offline bila memakai cache).
class RateNote extends StatelessWidget {
  const RateNote({super.key});
  @override
  Widget build(BuildContext context) {
    final code = context.watch<SettingsController>().currency;
    final r = context.watch<RatesController>();
    if (code == 'IDR') return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodySmall;
    if (prizeCurrency(code, r.rates) != code) {
      return Text('Kurs belum tersedia, nilai ditampilkan dalam IDR (mata uang dasar).', key: const Key('rate_note'), style: style);
    }
    final d = r.rates.rateDate;
    return Text(
      'Kurs per ${d == null ? '-' : formatDate(d)}${r.offline ? ' · offline (kurs tersimpan)' : ''}',
      key: const Key('rate_note'),
      style: style,
    );
  }
}

/// Hitung mundur ke [target], diperbarui tiap detik. Timer hanya berjalan saat widget terlihat: dihentikan saat
/// layar ditutup (dispose), saat tab/rute tersembunyi (TickerMode mati), dan saat aplikasi di latar belakang.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.target, this.now, this.style, this.prefix = 'Draw dalam ', this.builder});
  final DateTime target;
  final TextStyle? style;
  final String prefix;

  /// Tampilan sendiri untuk sisa waktu (mis. CountdownCard); null = teks "Draw dalam 2j 10m 05d".
  /// Dipanggil hanya selama target belum tercapai.
  final Widget Function(BuildContext context, Duration left)? builder;

  /// Hanya untuk tes: sumber waktu.
  final DateTime Function()? now;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> with WidgetsBindingObserver {
  Timer? _timer;
  bool _resumed = true;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
    if (_resumed && mounted) setState(() {});
  }

  /// Menyalakan atau mematikan timer sesuai keterlihatan.
  void _sync() {
    final visible = _resumed && TickerMode.valuesOf(context).enabled && widget.target.isAfter(_now());
    if (visible && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!widget.target.isAfter(_now())) _stop();
      });
    } else if (!visible) {
      _stop();
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.target.difference(_now());
    if (widget.builder != null && !left.isNegative && left != Duration.zero) return widget.builder!(context, left);
    return Text(
      left.isNegative || left == Duration.zero ? 'Waktu draw sudah tiba' : '${widget.prefix}${formatCountdown(left)}',
      key: const Key('countdown'),
      style: widget.style,
    );
  }
}
