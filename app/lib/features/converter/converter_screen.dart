import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/rates_controller.dart';
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
    Future.microtask(context.read<RatesController>().ensureFresh);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final rates = context.watch<RatesController>();
    final value = _value;
    final converted = value == null ? null : rates.rates.convert(value, _from, _to);
    final invalid = _amount.text.trim().isNotEmpty && (value == null || value < 0);

    DropdownButtonFormField<String> dropdown(Key key, String label, String current, ValueChanged<String> on) =>
        DropdownButtonFormField<String>(
          key: key,
          initialValue: current,
          decoration: InputDecoration(labelText: label),
          items: [for (final c in supportedCurrencies) DropdownMenuItem(value: c, child: Text(currencyName(c)))],
          onChanged: (v) => v == null ? null : setState(() => on(v)),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('amount_field'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Jumlah', errorText: invalid ? 'Masukkan angka yang valid.' : null),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: dropdown(const Key('from_currency'), 'Dari', _from, (v) => _from = v)),
          IconButton(
            key: const Key('swap_currency'),
            tooltip: 'Tukar',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => setState(() {
              final t = _from;
              _from = _to;
              _to = t;
            }),
          ),
          Expanded(child: dropdown(const Key('to_currency'), 'Ke', _to, (v) => _to = v)),
        ]),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (value == null || invalid)
                  const Text('-')
                else if (converted == null)
                  Text(rates.loading ? 'Memuat kurs...' : 'Kurs belum tersedia. Hubungkan ke internet sekali untuk mengambil kurs.',
                      key: const Key('currency_result'))
                else ...[
                  Text('${formatMoney(value, _from)} =', style: Theme.of(context).textTheme.bodyMedium),
                  Text(formatMoney(converted, _to),
                      key: const Key('currency_result'), style: Theme.of(context).textTheme.headlineSmall),
                ],
                const SizedBox(height: 8),
                _RateLabel(rates: rates),
              ],
            ),
          ),
        ),
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
      style: Theme.of(context).textTheme.bodySmall,
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
    String two(int n) => n.toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<AppZone>(
          key: const Key('source_zone'),
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
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('pick_date'),
              icon: const Icon(Icons.calendar_today),
              label: Text(formatDate(_date)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('pick_time'),
              icon: const Icon(Icons.schedule),
              label: Text('${two(_time.hour)}.${two(_time.minute)}'),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final z in AppZone.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 72, child: Text(z.title, style: TextStyle(fontWeight: z == _zone ? FontWeight.bold : null))),
                      Expanded(child: Text(formatInZone(instant, z), key: Key('conv_${z.name}'))),
                      Text(formatOffset(instant, z), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Waktu musim panas London (GMT/BST) dihitung otomatis dari data zona waktu IANA.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
