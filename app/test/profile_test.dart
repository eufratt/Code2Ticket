import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/images/photo_compress.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/profile/profile_controller.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:code2ticket/features/profile/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/display.dart';

Uint8List noisyPng(int w, int h, {int seed = 1}) {
  final rnd = Random(seed);
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256);
  }
  return Uint8List.fromList(img.encodePng(image));
}

AppUser user({String name = 'Eufrat Aja', String? photo, List<String> badges = const []}) => AppUser(
    id: 'u1', username: 'eufrat', email: 'e@x.id', fullName: name, photoUrl: photo, role: 'user', xp: 120, level: 1, badges: badges);

void main() {
  group('compressProfilePhoto: <= 512 px, JPEG, <= 150 KB', () {
    test('foto besar penuh derau diperkecil: sisi terpanjang 512, JPEG, <= 150 KB', () {
      final out = compressProfilePhoto(noisyPng(1600, 1200));
      expect(out.length, lessThanOrEqualTo(150 * 1024));
      expect(out.sublist(0, 3), [0xff, 0xd8, 0xff]); // JPEG
      final back = img.decodeJpg(out)!;
      expect([back.width, back.height], [512, 384]); // rasio 4:3 terjaga
    });

    test('foto potret: sisi terpanjang (tinggi) 512', () {
      final back = img.decodeJpg(compressProfilePhoto(noisyPng(600, 1200)))!;
      expect([back.width, back.height], [256, 512]);
    });

    test('gambar kecil tidak diperbesar', () {
      final back = img.decodeJpg(compressProfilePhoto(noisyPng(100, 80)))!;
      expect([back.width, back.height], [100, 80]);
    });

    test('derau 1024x1024 (sulit dikompres) tetap <= 150 KB', () {
      expect(compressProfilePhoto(noisyPng(1024, 1024, seed: 7)).length, lessThanOrEqualTo(150 * 1024));
    });

    test('batas yang lebih ketat dipatuhi dengan mengecilkan ukuran lebih jauh', () {
      final out = compressProfilePhoto(noisyPng(800, 800), maxBytes: 20 * 1024);
      expect(out.length, lessThanOrEqualTo(20 * 1024));
    });

    test('berkas bukan gambar -> FormatException', () {
      expect(() => compressProfilePhoto(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
    });
  });

  group('alamat foto dan inisial', () {
    test('resolvePhotoUrl', () {
      expect(resolvePhotoUrl('/users/u1/photo?v=5', base: 'https://api.test'), 'https://api.test/users/u1/photo?v=5');
      expect(resolvePhotoUrl('/users/u1/photo?v=5', base: 'https://api.test/'), 'https://api.test/users/u1/photo?v=5');
      expect(resolvePhotoUrl('https://cdn.x/a.jpg', base: 'https://api.test'), 'https://cdn.x/a.jpg');
      expect(resolvePhotoUrl(null), isNull);
      expect(resolvePhotoUrl(''), isNull);
    });
    test('initialsOf', () {
      expect(initialsOf('Eufrat Aja'), 'EA');
      expect(initialsOf('budi'), 'B');
      expect(initialsOf('  Ayu  Lestari Dewi '), 'AD');
      expect(initialsOf(''), '?');
    });
    test('AppUser.fromJson membaca photo_url dan badges secara defensif', () {
      final u = AppUser.fromJson({
        'id': 'u', 'username': 'a', 'email': 'e', 'full_name': 'F', 'role': 'user',
        'photo_url': '/users/u/photo?v=1', 'badges': ['first_ticket', 5, null, 'early_bird'],
      });
      expect(u.photoUrl, '/users/u/photo?v=1');
      expect(u.badges, ['first_ticket', 'early_bird']);
      expect(AppUser.fromJson({'id': 'u', 'username': 'a', 'email': 'e', 'full_name': 'F', 'role': 'user', 'badges': 'rusak'}).badges, isEmpty);
    });
  });

  group('ProfileController', () {
    late FakeApi api;
    late FakeAuth auth;
    ProfileController make(Future<Map<String, dynamic>> Function(String m, String p, dynamic b) h,
        {Future<Uint8List> Function(Uint8List)? compress}) {
      api = FakeApi(h);
      auth = FakeAuth(api)..user = user();
      return ProfileController(AuthedApi(api, auth), auth, compress: compress ?? (b) async => b);
    }

    Map<String, dynamic> userJson(String name, {String? photo}) => {
          'ok': true,
          'user': {
            'id': 'u1', 'username': 'eufrat', 'email': 'e@x.id', 'full_name': name, 'photo_url': photo, 'role': 'user', 'xp': 120, 'level': 1,
            'badges': ['first_ticket'],
          },
        };

    test('ubah nama: PATCH /me dengan nama terpangkas, pengguna diperbarui', () async {
      final c = make((m, p, b) async => userJson('Nama Baru'));
      expect(await c.updateName('  Nama Baru  '), isNull);
      final call = api.calls.single;
      expect([call.method, call.path, call.body], ['PATCH', '/me', {'full_name': 'Nama Baru'}]);
      expect(auth.user!.fullName, 'Nama Baru');
      expect(auth.user!.badges, ['first_ticket']);
    });

    test('nama kosong / lebih dari 100 karakter ditolak di klien tanpa permintaan', () async {
      final c = make((m, p, b) async => fail('tidak boleh dipanggil'));
      expect(await c.updateName('   '), contains('wajib diisi'));
      expect(await c.updateName('x' * 101), contains('maks. 100'));
      expect(api.calls, isEmpty);
      expect(auth.user!.fullName, 'Eufrat Aja');
    });

    test('galat server dan jaringan menjadi pesan, nama lama tetap', () async {
      var c = make((m, p, b) async => {'ok': false, 'error': 'invalid_input', 'field': 'full_name'});
      expect(await c.updateName('Baru'), contains('Nama lengkap'));
      c = make((m, p, b) async => throw NetworkException('Tidak ada koneksi internet.'));
      expect(await c.updateName('Baru'), 'Tidak ada koneksi internet.');
      expect(auth.user!.fullName, 'Eufrat Aja');
    });

    test('unggah foto: PUT /me/photo berisi JPEG hasil kompresi, photo_url baru dipakai', () async {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9]);
      Uint8List? received;
      final c = make((m, p, b) async {
        received = Uint8List.fromList(b as List<int>);
        return userJson('Eufrat Aja', photo: '/users/u1/photo?v=99');
      }, compress: (_) async => jpeg);
      expect(await c.uploadPhoto(Uint8List.fromList([9, 9, 9])), isNull);
      expect([api.calls.single.method, api.calls.single.path, api.calls.single.retry], ['PUT', '/me/photo', false]);
      expect(received, jpeg);
      expect(auth.user!.photoUrl, '/users/u1/photo?v=99');
    });

    test('foto rusak: pesan, tidak ada permintaan; hasil kompresi terlalu besar ditolak', () async {
      var c = make((m, p, b) async => fail('tidak boleh dipanggil'),
          compress: (_) async => throw const FormatException('Berkas bukan gambar yang dapat dibaca.'));
      expect(await c.uploadPhoto(Uint8List(3)), 'Berkas bukan gambar yang dapat dibaca.');
      c = make((m, p, b) async => fail('tidak boleh dipanggil'), compress: (_) async => Uint8List(150 * 1024 + 1));
      expect(await c.uploadPhoto(Uint8List(3)), contains('terlalu besar'));
      expect(api.calls, isEmpty);
    });

    test('galat server: payload_too_large, terlalu banyak percobaan, jaringan', () async {
      var c = make((m, p, b) async => {'ok': false, 'error': 'payload_too_large'});
      expect(await c.uploadPhoto(Uint8List(3)), contains('150 KB'));
      c = make((m, p, b) async => {'ok': false, 'error': 'too_many_requests'});
      expect(await c.uploadPhoto(Uint8List(3)), contains('Terlalu banyak'));
      c = make((m, p, b) async => throw NetworkException('Koneksi terlalu lama. Coba lagi.'));
      expect(await c.uploadPhoto(Uint8List(3)), 'Koneksi terlalu lama. Coba lagi.');
      expect(auth.user!.photoUrl, isNull);
    });

    test('sesi berakhir (401) saat unggah: logout, tanpa pesan galat', () async {
      final c = make((m, p, b) async => throw InvalidSessionException());
      expect(await c.uploadPhoto(Uint8List(3)), isNull);
      expect(auth.invalidated, 1);
      expect(c.saving, isFalse);
    });

    test('dua unggahan bersamaan: hanya satu yang berjalan', () async {
      final gate = Completer<Map<String, dynamic>>();
      final c = make((m, p, b) => gate.future);
      final first = c.uploadPhoto(Uint8List(3));
      await Future<void>.delayed(Duration.zero);
      expect(await c.uploadPhoto(Uint8List(3)), contains('Sedang menyimpan'));
      gate.complete(userJson('Eufrat Aja', photo: '/users/u1/photo?v=1'));
      expect(await first, isNull);
      expect(api.calls, hasLength(1));
    });
  });

  group('ProfileScreen', () {
    late FakeApi api;
    late FakeAuth auth;

    Future<void> pump(WidgetTester tester, Future<Map<String, dynamic>> Function(String, String, dynamic) h,
        {PhotoPicker? picker, AppUser? u}) async {
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      api = FakeApi(h);
      auth = FakeAuth(api)..user = u ?? user(badges: ['first_ticket', 'early_bird']);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
          ...displayProviders(),
        ],
        child: MaterialApp(home: ProfileScreen(picker: picker ?? (_) async => null, compress: (b) async => b)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('menampilkan nama, username, email, role, level, XP, lencana, dan inisial bila belum ada foto', (tester) async {
      await pump(tester, (m, p, b) async => {'ok': true});
      expect(find.text('Eufrat Aja'), findsOneWidget);
      expect(find.text('@eufrat'), findsOneWidget);
      expect(find.text('e@x.id'), findsOneWidget);
      expect(find.text('user'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('120 XP'), findsOneWidget);
      expect(find.text('First Ticket'), findsOneWidget);
      expect(find.text('Early Bird'), findsOneWidget);
      expect(find.byKey(const Key('avatar_initials')), findsOneWidget);
      expect(find.text('EA'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Pengaturan'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Pengaturan'), findsOneWidget);
      // Dipindah ke bottom navigation / menu fitur Home: tidak ganda di Profil.
      for (final t in ['Konverter', 'Saran & Kesan', 'Game', 'Keluar']) {
        expect(find.text(t), findsNothing, reason: t);
      }
    });

    testWidgets('ubah nama: dialog -> PATCH /me -> nama baru tampil', (tester) async {
      await pump(tester, (m, p, b) async => {
            'ok': true,
            'user': {'id': 'u1', 'username': 'eufrat', 'email': 'e@x.id', 'full_name': 'Nama Baru', 'role': 'user', 'xp': 120, 'level': 1},
          });
      await tester.tap(find.byKey(const Key('edit_name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name_field')), 'Nama Baru');
      await tester.tap(find.byKey(const Key('save_name')));
      await tester.pumpAndSettle();
      expect(api.calls.single.body, {'full_name': 'Nama Baru'});
      expect(find.text('Nama Baru'), findsOneWidget);
      expect(find.text('Nama diperbarui.'), findsOneWidget);
    });

    testWidgets('nama kosong: pesan kesalahan, tidak ada permintaan', (tester) async {
      await pump(tester, (m, p, b) async => fail('tidak boleh dipanggil'));
      await tester.tap(find.byKey(const Key('edit_name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('name_field')), '   ');
      await tester.tap(find.byKey(const Key('save_name')));
      await tester.pumpAndSettle();
      expect(find.textContaining('wajib diisi'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('ganti foto dari galeri: lembar pilihan -> PUT /me/photo -> foto diperbarui', (tester) async {
      ImageSource? asked;
      await pump(
        tester,
        (m, p, b) async => {
              'ok': true,
              'user': {
                'id': 'u1', 'username': 'eufrat', 'email': 'e@x.id', 'full_name': 'Eufrat Aja', 'role': 'user', 'xp': 120, 'level': 1,
                'photo_url': '/users/u1/photo?v=7',
              },
            },
        picker: (s) async {
          asked = s;
          return Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
        },
      );
      await tester.tap(find.byKey(const Key('avatar_button')));
      await tester.pumpAndSettle();
      expect(find.text('Ambil foto (kamera)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo_gallery')));
      await tester.pumpAndSettle();
      expect(asked, ImageSource.gallery);
      expect(api.calls.single.path, '/me/photo');
      expect(auth.user!.photoUrl, '/users/u1/photo?v=7');
      expect(find.text('Foto profil diperbarui.'), findsOneWidget);
    });

    testWidgets('kamera tidak bisa dibuka (izin ditolak / tidak ada): pesan jelas, tidak ada unggahan', (tester) async {
      await pump(tester, (m, p, b) async => fail('tidak boleh dipanggil'), picker: (_) async => throw Exception('no camera'));
      await tester.tap(find.byKey(const Key('avatar_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo_camera')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tidak bisa membuka kamera'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('pemilihan dibatalkan: tidak ada permintaan', (tester) async {
      await pump(tester, (m, p, b) async => fail('tidak boleh dipanggil'));
      await tester.tap(find.byKey(const Key('avatar_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo_gallery')));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
    });
  });
}
