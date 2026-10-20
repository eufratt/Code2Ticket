import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/format.dart' show parseIdNumber;
import '../../core/currency/rates_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../core/time/zones.dart';

/// Konverter (dari Profil): tab Mata Uang dan tab Waktu.
class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Konverter'),
          bottom: const TabBar(tabs: [Tab(text: 'Mata Uang'), Tab(text: 'Waktu')]),
        ),
        body: const TabBarView(children: [CurrencyConverter(), TimeConverter()]),
      ),
    );
  }
}

/// Mata uang: jumlah, dari, ke, tukar, hasil langsung. Kurs Frankfurter (cache bila offline).
class CurrencyConverter extends StatefulWidget {
  const CurrencyConverter({super.key});
  @override
  State<CurrencyConverter> createState() => _CurrencyConverterState();
}

class _CurrencyConverterState extends State<CurrencyConverter> {
  final _amount = TextEditingController(text: '1');
  String _from = 'USD', _to = 'IDR';

  @override
  void initState() {
    super.initState();
    final rates = context.read<RatesController>();
    Future.microtask(() => rates.ensureFresh(force: true));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value => parseIdNumber(_amount.text);

  @override
  Widget build(BuildContext context) {
    final rates = context.watch<RatesController>();
    final value = _value;
    final converted = value == null ? null : rates.rates.convert(value, _from, _to);
    final invalid = _amount.text.trim().isNotEmpty && (value == null || value < 0);

    DropdownButtonFormField<String> dropdown(Key key, String label, String current, ValueChanged<String> on) =>
        DropdownButtonFormField<String>(
          key: key,
          isExpanded: true,
          initialValue: current,
          decoration: InputDecoration(labelText: label),
          items: [for (final c in supportedCurrencies) DropdownMenuItem(value: c, child: Text(currencyName(c)))],
          onChanged: (v) => v == null ? null : setState(() => on(v)),
        );

    final theme = Theme.of(context);
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(Spacing.screen),
      children: [
        // Hasil besar di atas.
        SurfaceCard(
          color: c.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (value == null || invalid)
                Text('-', style: theme.textTheme.displaySmall?.copyWith(color: c.onPrimaryContainer))
              else if (converted == null)
                Text(rates.loading ? 'Memuat kurs...' : 'Kurs belum tersedia. Hubungkan ke internet sekali untuk mengambil kurs.',
                    key: const Key('currency_result'), style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer))
              else ...[
                Text('${formatMoney(value, _from)} =', style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer)),
                const SizedBox(height: Spacing.s4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMoney(converted, _to),
                    key: const Key('currency_result'),
                    style: AppTypography.tabular(theme.textTheme.displaySmall!.copyWith(color: c.onPrimaryContainer)),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.sectionGap),
        TextField(
          key: const Key('amount_field'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Jumlah', errorText: invalid ? 'Masukkan angka yang valid.' : null),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Spacing.s12),
        dropdown(const Key('from_currency'), 'Dari', _from, (v) => _from = v),
        Align(
          child: IconButton(
            key: const Key('swap_currency'),
            tooltip: 'Tukar mata uang asal dan tujuan',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() {
              final t = _from;
              _from = _to;
              _to = t;
            }),
          ),
        ),
        dropdown(const Key('to_currency'), 'Ke', _to, (v) => _to = v),
        const SizedBox(height: Spacing.s16),
        // Keterangan kurs/tanggal dan label offline di kaki.
        _RateLabel(rates: rates),
      ],
    );
  }
}

class _RateLabel extends StatelessWidget {
  const _RateLabel({required this.rates});
  final RatesController rates;
  @override
  Widget build(BuildContext context) {
    if (!rates.hasRates) return const SizedBox.shrink();
    final d = rates.rates.rateDate;
    return Text(
      'Kurs per ${d == null ? '-' : formatDate(d)}${rates.offline ? ' · offline (kurs tersimpan)' : ''} · Frankfurter',
      key: const Key('converter_rate_label'),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.muted),
    );
  }
}

/// Waktu: pilih tanggal dan jam di satu zona, lihat di keempat zona sekaligus.
class TimeConverter extends StatefulWidget {
  const TimeConverter({super.key, this.initial});

  /// Hanya untuk tes: waktu awal (instan).
  final DateTime? initial;
  @override
  State<TimeConverter> createState() => _TimeConverterState();
}

class _TimeConverterState extends State<TimeConverter> {
  AppZone _zone = AppZone.wib;
  late DateTime _date;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _setFrom(widget.initial ?? DateTime.now());
  }

  void _setFrom(DateTime instant) {
    final t = inZone(instant, _zone);
    _date = DateTime(t.year, t.month, t.day);
    _time = TimeOfDay(hour: t.hour, minute: t.minute);
  }

  DateTime get _instant => instantFromWallClock(_zone, _date.year, _date.month, _date.day, _time.hour, _time.minute);

  @override
  Widget build(BuildContext context) {
    final instant = _instant;
    final theme = Theme.of(context);
    final c = context.colors;
    String two(int n) => n.toString().padLeft(2, '0');
    final dateButton = PrimaryButton(
      key: const Key('pick_date'),
      label: formatDate(_date),
      icon: Icons.calendar_today,
      variant: ButtonVariant.secondary,
      onPressed: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: _date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d != null) setState(() => _date = d);
      },
    );
    final timeButton = PrimaryButton(
      key: const Key('pick_time'),
      label: '${two(_time.hour)}.${two(_time.minute)}',
      icon: Icons.schedule,
      variant: ButtonVariant.secondary,
      onPressed: () async {
        final t = await showTimePicker(context: context, initialTime: _time);
        if (t != null) setState(() => _time = t);
      },
    );
    // Skala font besar: tombol ditumpuk supaya label tidak terpotong.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    return ListView(
      padding: const EdgeInsets.all(Spacing.screen),
      children: [
        DropdownButtonFormField<AppZone>(
          key: const Key('source_zone'),
          isExpanded: true,
          initialValue: _zone,
          decoration: const InputDecoration(labelText: 'Zona asal'),
          items: [for (final z in AppZone.values) DropdownMenuItem(value: z, child: Text(z.title))],
          onChanged: (z) => z == null
              ? null
              : setState(() {
                  final keep = _instant; // pertahankan saat yang sama, tampilkan di zona baru
                  _zone = z;
                  _setFrom(keep);
                }),
        ),
        const SizedBox(height: Spacing.s12),
        if (stacked) ...[dateButton, const SizedBox(height: Spacing.s8), timeButton] else Row(children: [
          Expanded(child: dateButton),
          const SizedBox(width: Spacing.s12),
          Expanded(child: timeButton),
        ]),
        const SizedBox(height: Spacing.sectionGap),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, z) in AppZone.values.indexed) ...[
                if (i > 0) const Divider(height: Spacing.s24),
                Row(children: [
                  Expanded(child: Text(z.title, style: theme.textTheme.titleSmall?.copyWith(color: z == _zone ? c.primary : null))),
                  Text(formatOffset(instant, z), style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                ]),
                const SizedBox(height: Spacing.s4),
                Text(formatInZone(instant, z), key: Key('conv_${z.name}'), style: AppTypography.tabular(theme.textTheme.bodyLarge!)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.s12),
        Text('Waktu musim panas London (GMT/BST) dihitung otomatis dari data zona waktu IANA.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
      ],
    );
  }
}
