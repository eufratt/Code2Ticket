
import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/core/theme/app_colors.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/core/widgets/widgets.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/display.dart';
import '../support/ui.dart';

class _Auth extends AuthController {
  _Auth() : super(ApiClient(), SessionStore());
}

Widget host(Widget child) => themedApp(Scaffold(body: child));

void main() {
  setUpAll(() => displayProviders());

  group('StatusChip', () {
    testWidgets('semua status pada tabel DESIGN.md: teks + ikon, warna sesuai nada', (tester) async {
      await tester.pumpWidget(host(SingleChildScrollView(
        child: Column(children: [for (final s in AppStatus.values) StatusChip(s, key: ValueKey(s))]),
      )));
      final colors = AppColors.light;
      for (final s in AppStatus.values) {
        final chip = find.byKey(ValueKey(s));
        expect(find.descendant(of: chip, matching: find.text(s.label)), findsOneWidget, reason: s.name);
        expect(find.descendant(of: chip, matching: find.byIcon(s.icon)), findsOneWidget, reason: '${s.name} punya ikon');
        final bg = tester.widget<DecoratedBox>(find.descendant(of: chip, matching: find.byType(DecoratedBox)).first);
        final expected = StatusChip.colorsOf(colors, s.tone).bg;
        expect((bg.decoration as ShapeDecoration).color, expected, reason: s.name);
        final text = tester.widget<Text>(find.descendant(of: chip, matching: find.text(s.label)));
        expect(text.style!.color, StatusChip.colorsOf(colors, s.tone).fg, reason: s.name);
      }
      // Tabel DESIGN.md: nada tiap status.
      expect({for (final s in AppStatus.values) s.name: s.tone}, {
        'giveawayUpcoming': StatusTone.info,
        'giveawayActive': StatusTone.success,
        'giveawayDrawSoon': StatusTone.warning,
        'giveawayWaitingDraw': StatusTone.warning,
        'giveawayFinished': StatusTone.neutral,
        'ticketEligible': StatusTone.info,
        'ticketWaiting': StatusTone.warning,
        'ticketWon': StatusTone.success,
        'ticketNotSelected': StatusTone.neutral,
        'verified': StatusTone.success,
        'mismatch': StatusTone.error,
      });
      expect(AppStatus.ticketWon.icon, Icons.emoji_events);
    });

    testWidgets('di tema gelap memakai pasangan warna gelap', (tester) async {
      await setViewport(tester, brightness: Brightness.dark);
      await tester.pumpWidget(host(const StatusChip(AppStatus.giveawayActive)));
      final bg = tester.widget<DecoratedBox>(find.descendant(of: find.byType(StatusChip), matching: find.byType(DecoratedBox)).first);
      expect((bg.decoration as ShapeDecoration).color, AppColors.dark.statusSuccess.bg);
    });

    testWidgets('StatusChip.custom', (tester) async {
      await tester.pumpWidget(host(const StatusChip.custom(label: 'admin', tone: StatusTone.info, icon: Icons.shield_outlined)));
      expect(find.text('admin'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });
  });

  group('TicketCard', () {
    Widget card({VoidCallback? onTap}) => host(Padding(
          padding: const EdgeInsets.all(16),
          child: TicketCard(
            title: 'Demo: Laptop Gaming Giveaway',
            category: 'gaming',
            ticketNumber: '#000012',
            status: AppStatus.ticketWaiting,
            prizeText: 'Rp 21.587.000',
            subtitle: 'Draw 20 Okt 2026, 20.00 WIB',
            onTap: onTap,
          ),
        ));

    testWidgets('menampilkan nama, hadiah, nomor tiket, dan status; seluruh kartu dapat diketuk', (tester) async {
      var taps = 0;
      await tester.pumpWidget(card(onTap: () => taps++));
      expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
      expect(find.text('Rp 21.587.000'), findsOneWidget);
      expect(find.text('#000012'), findsOneWidget);
      expect(find.text('Menunggu draw'), findsOneWidget);
      await tester.tap(find.text('Demo: Laptop Gaming Giveaway'));
      await tester.tap(find.text('#000012')); // bagian bawah (setelah garis putus) juga mengetuk kartu
      expect(taps, 2);
    });

    test('lekukan sobekan: titik sudut garis putus terpotong, tengah tetap isi, di kedua bagian', () {
      const size = Size(300, 120);
      final top = ticketPartPath(size, top: true);
      final bottom = ticketPartPath(size, top: false);
      // Sisi garis putus: di sudut (0,h)/(w,h) bagian atas dan (0,0)/(w,0) bagian bawah ada lekukan radius 10.
      expect(top.contains(const Offset(1, 119)), isFalse);
      expect(top.contains(const Offset(299, 119)), isFalse);
      expect(top.contains(const Offset(150, 119)), isTrue);
      expect(top.contains(const Offset(1, 100)), isTrue); // di luar lekukan (> 10 dp dari garis)
      expect(bottom.contains(const Offset(1, 1)), isFalse);
      expect(bottom.contains(const Offset(299, 1)), isFalse);
      expect(bottom.contains(const Offset(150, 1)), isTrue);
      // Sisi luar tetap bersudut membulat (radius 16).
      expect(top.contains(const Offset(1, 1)), isFalse);
      expect(bottom.contains(const Offset(1, 119)), isFalse);
      expect(top.contains(const Offset(20, 20)), isTrue);
    });

    for (final b in Brightness.values) {
      testWidgets('satu bentuk selebar penuh: bagian atas dan bawah sama lebar, sejajar, di tema ${b.name}', (tester) async {
        await setViewport(tester, brightness: b);
        // Isi bawah sengaja pendek (Wrap tanpa lebar tetap): dulu menyusut dan bergeser.
        await tester.pumpWidget(host(const Padding(
          padding: EdgeInsets.all(16),
          child: TicketCard(title: 'A', category: null, ticketNumber: '#1', status: AppStatus.ticketWon),
        )));
        final parts = find.descendant(of: find.byType(TicketCard), matching: find.byWidgetPredicate((w) => w is ClipPath && w.clipper.runtimeType.toString() == '_TicketPartClipper'));
        expect(parts, findsNWidgets(2));
        final topRect = tester.getRect(parts.at(0)), bottomRect = tester.getRect(parts.at(1));
        final card = tester.getRect(find.byType(TicketCard));
        expect(topRect.width, 360 - 32);
        expect(bottomRect.width, topRect.width);
        expect(bottomRect.left, topRect.left);
        expect(card.width, topRect.width);
        expect(bottomRect.top, topRect.bottom); // menyambung tanpa celah
      });
    }

    testWidgets('nomor tiket memakai angka tabular', (tester) async {
      await tester.pumpWidget(card());
      final t = tester.widget<Text>(find.byKey(const Key('ticket_card_number')));
      expect(t.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('tanpa onTap: tidak ada chevron, tidak dibaca sebagai tombol', (tester) async {
      await tester.pumpWidget(card());
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  group('EmptyState / ErrorState', () {
    testWidgets('EmptyState: ikon 64, judul, penjelasan, satu aksi', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(EmptyState(
        icon: Icons.confirmation_number_outlined,
        title: 'Belum ada tiket',
        message: 'Masukkan kode lewat tombol di tengah.',
        actionLabel: 'Masukkan kode',
        onAction: () => tapped = true,
      )));
      expect(find.text('Belum ada tiket'), findsOneWidget);
      expect(find.text('Masukkan kode lewat tombol di tengah.'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.confirmation_number_outlined)).size, 64);
      await tester.tap(find.text('Masukkan kode'));
      expect(tapped, isTrue);
    });

    testWidgets('EmptyState tanpa aksi tidak menampilkan tombol', (tester) async {
      await tester.pumpWidget(host(const EmptyState(icon: Icons.search_off, title: 'Kosong')));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('ErrorState: pesan jelas + Coba lagi', (tester) async {
      var retried = 0;
      await tester.pumpWidget(host(ErrorState(message: 'Tidak ada koneksi internet.', onRetry: () => retried++)));
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      expect(retried, 1);
      expect(find.text('Server sedang bangun, tunggu sebentar...'), findsNothing);
    });

    testWidgets('ErrorState: "Server sedang bangun" muncul saat isWakingUp (>5 detik)', (tester) async {
      final auth = _Auth();
      await tester.pumpWidget(ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: host(ErrorState(message: 'Gagal.', onRetry: () {})),
      ));
      expect(find.text('Server sedang bangun, tunggu sebentar...'), findsNothing);
      auth.setWakingUp(true);
      await tester.pump();
      expect(find.text('Server sedang bangun, tunggu sebentar...'), findsOneWidget);
    });
  });

  group('SkeletonLoader', () {
    testWidgets('tiga bentuk kerangka tampil tanpa spinner, dibaca "Memuat"', (tester) async {
      for (final shape in SkeletonShape.values) {
        await tester.pumpWidget(host(SkeletonLoader(shape: shape, count: 2)));
        expect(find.byType(SkeletonBox), findsWidgets, reason: shape.name);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.bySemanticsLabel('Memuat'), findsOneWidget);
      }
    });

    testWidgets('berdenyut; berhenti bila "kurangi animasi" aktif', (tester) async {
      await tester.pumpWidget(host(const SkeletonLoader()));
      Color color() {
        final box = find.descendant(of: find.byType(SkeletonBox), matching: find.byType(Container)).first;
        return (tester.widget<Container>(box).decoration as BoxDecoration).color!;
      }

      final a = color();
      await tester.pump(const Duration(milliseconds: 550));
      expect(color(), isNot(a));

      // Tanpa animasi: tidak ada ticker, pumpAndSettle selesai.
      await tester.pumpWidget(themedApp(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const Scaffold(body: SkeletonLoader()),
      )));
      await tester.pumpAndSettle();
    });
  });

  group('CategoryBanner', () {
    testWidgets('tanpa gambar: gradien kategori + ikon', (tester) async {
      await tester.pumpWidget(host(const CategoryBanner(category: 'gaming')));
      expect(find.byKey(const Key('banner_gradient_gaming')), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports), findsOneWidget);
      expect(find.byKey(const Key('banner_image')), findsNothing);
    });

    testWidgets('setiap kategori punya ikon sendiri; backend tech/food dipetakan; tak dikenal = lainnya', (tester) async {
      const expected = {
        'gaming': ('gaming', Icons.sports_esports),
        'travel': ('travel', Icons.flight),
        'tech': ('elektronik', Icons.laptop_mac),
        'fashion': ('fashion', Icons.checkroom),
        'food': ('makanan', Icons.restaurant),
        'lifestyle': ('lainnya', Icons.card_giftcard),
        'other': ('lainnya', Icons.card_giftcard),
        'aneh': ('lainnya', Icons.card_giftcard),
      };
      for (final e in expected.entries) {
        await tester.pumpWidget(host(CategoryBanner(category: e.key)));
        expect(find.byKey(Key('banner_gradient_${e.value.$1}')), findsOneWidget, reason: e.key);
        expect(find.byIcon(e.value.$2), findsOneWidget, reason: e.key);
      }
    });

    testWidgets('dengan URL gambar: gambar ditampilkan; gagal dimuat jatuh ke gradien (bukan kotak kosong)', (tester) async {
      await tester.pumpWidget(host(const CategoryBanner(category: 'travel', imageUrl: 'http://localhost:1/banner.png')));
      expect(find.byKey(const Key('banner_image')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const Key('banner_gradient_travel')), findsOneWidget);
    });

    testWidgets('URL kosong dianggap tanpa gambar; tinggi tetap 180 untuk Detail', (tester) async {
      await tester.pumpWidget(host(const CategoryBanner(category: 'food', imageUrl: '  ', height: 180)));
      expect(find.byKey(const Key('banner_image')), findsNothing);
      expect(tester.getSize(find.byType(CategoryBanner)).height, 180);
    });

    testWidgets('rasio 16:9 untuk kartu', (tester) async {
      await tester.pumpWidget(host(const Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: CategoryBanner(category: 'fashion')))));
      expect(tester.getSize(find.byType(CategoryBanner)), const Size(320, 180));
    });
  });

  group('PrimaryButton', () {
    testWidgets('loading: spinner, nonaktif, tidak bisa kirim ganda', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(PrimaryButton(label: 'Kirim', loading: true, onPressed: () => taps++)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Kirim'), findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('varian primer, sekunder, teks; tinggi 52', (tester) async {
      await tester.pumpWidget(host(Column(children: [
        PrimaryButton(label: 'A', onPressed: () {}),
        PrimaryButton(label: 'B', variant: ButtonVariant.secondary, onPressed: () {}),
        PrimaryButton(label: 'C', variant: ButtonVariant.text, onPressed: () {}),
        PrimaryButton(label: 'D', icon: Icons.add, onPressed: () {}),
      ])));
      expect(find.byType(FilledButton), findsNWidgets(2));
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(FilledButton, 'A')).height, 52);
      expect(tester.getSize(find.widgetWithText(OutlinedButton, 'B')).height, 52);
    });

    testWidgets('onPressed null = nonaktif', (tester) async {
      await tester.pumpWidget(host(const PrimaryButton(label: 'X', onPressed: null)));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    });
  });

  group('SectionHeader, OfflineBanner, CountdownCard', () {
    testWidgets('SectionHeader: judul + aksi opsional', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(Column(children: [
        SectionHeader('Segera draw', actionLabel: 'Lihat semua', onAction: () => tapped++),
        const SectionHeader('Tanpa aksi'),
      ])));
      await tester.tap(find.text('Lihat semua'));
      expect(tapped, 1);
      expect(find.text('Tanpa aksi'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(TextButton, 'Lihat semua')).height, greaterThanOrEqualTo(48));
    });

    testWidgets('OfflineBanner: "Data offline · diperbarui <waktu>" memakai zona pilihan', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(),
        child: host(OfflineBanner(cachedAt: DateTime.utc(2026, 10, 19, 4))),
      ));
      expect(find.text('Data offline · diperbarui 19 Okt 2026, 11.00 WIB'), findsOneWidget);
    });

    testWidgets('CountdownCard: hari/jam/menit/detik berjalan; selesai -> "Waktu draw sudah tiba"', (tester) async {
      final target = DateTime(2026, 10, 21, 12);
      var now = target.subtract(const Duration(days: 1, hours: 2, minutes: 3, seconds: 4));
      await tester.pumpWidget(host(CountdownCard(target: target, now: () => now)));
      expect(find.text('Draw dalam'), findsOneWidget);
      for (final t in ['01', '02', '03', '04', 'hari', 'jam', 'menit', 'detik']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('05'), findsNothing);
      expect(find.text('03'), findsNWidgets(2)); // menit 03, detik 03
      now = target;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Waktu draw sudah tiba'), findsOneWidget);
      await tester.pumpWidget(host(const SizedBox())); // timer berhenti saat layar ditutup
    });
  });

  group('tanpa overflow pada 360/428 dp dan font 1,3x, terang + gelap', () {
    for (final v in layoutVariants) {
      testWidgets('komponen: ${v.name}', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        await tester.pumpWidget(MultiProvider(
          providers: displayProviders(),
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              body: ListView(padding: const EdgeInsets.all(16), children: [
                TicketCard(
                  title: 'Giveaway dengan judul yang sangat panjang sekali untuk menguji pemotongan baris',
                  category: 'travel',
                  ticketNumber: '#000012',
                  status: AppStatus.ticketNotSelected,
                  prizeText: 'Rp 20.000.000 · Paket liburan',
                  subtitle: 'Draw 20 Okt 2026, 20.00 WIB',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                CountdownCard(target: DateTime.now().add(const Duration(days: 2, hours: 3))),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [for (final s in AppStatus.values) StatusChip(s)]),
                const SectionHeader('Judul bagian yang cukup panjang', actionLabel: 'Lihat semua', onAction: _noop),
                const SizedBox(height: 200, child: ErrorState(message: 'Tidak ada koneksi internet. Periksa jaringanmu lalu coba lagi.', onRetry: _noop)),
              ]),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: v.name);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}

void _noop() {}
