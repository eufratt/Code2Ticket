import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/geocoding/geocoder.dart';
import 'package:code2ticket/core/geo.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_location.dart';

void main() {
  group('LocationService: semua keadaan izin dengan layanan lokasi palsu', () {
    test('izin sudah diberikan: posisi didapat tanpa dialog', () async {
      final g = FakeGateway(permission: GatewayPermission.granted);
      final fix = await LocationService(g).locate();
      expect(fix.ok, isTrue);
      expect([fix.lat, fix.lng], [-6.2, 106.8]);
      expect(g.requests, 0);
    });

    test('belum diminta + prompt: dialog muncul, disetujui -> posisi didapat', () async {
      final g = FakeGateway(permission: GatewayPermission.denied, afterRequest: GatewayPermission.granted);
      final fix = await LocationService(g).locate();
      expect(g.requests, 1);
      expect(fix.status, LocationStatus.granted);
    });

    test('belum diminta + prompt: ditolak di dialog -> denied, tanpa mengambil posisi', () async {
      final g = FakeGateway(permission: GatewayPermission.denied, afterRequest: GatewayPermission.denied);
      final fix = await LocationService(g).locate();
      expect(fix.status, LocationStatus.denied);
      expect(fix.ok, isFalse);
      expect(g.positions, 0);
    });

    test('ditolak permanen di dialog -> deniedForever', () async {
      final g = FakeGateway(permission: GatewayPermission.denied, afterRequest: GatewayPermission.deniedForever);
      expect((await LocationService(g).locate()).status, LocationStatus.deniedForever);
    });

    test('sudah ditolak permanen: tidak memunculkan dialog lagi', () async {
      final g = FakeGateway(permission: GatewayPermission.deniedForever);
      expect((await LocationService(g).locate()).status, LocationStatus.deniedForever);
      expect(g.requests, 0);
    });

    test('layanan lokasi mati -> serviceOff (tanpa meminta izin)', () async {
      final g = FakeGateway(service: false, permission: GatewayPermission.granted);
      expect((await LocationService(g).locate()).status, LocationStatus.serviceOff);
      expect(g.requests + g.positions, 0);
    });

    test('tanpa prompt (Input Code): izin belum ada -> denied, TIDAK pernah memunculkan dialog atau mengambil posisi', () async {
      final g = FakeGateway(permission: GatewayPermission.denied);
      final fix = await LocationService(g).locate(prompt: false);
      expect(fix.ok, isFalse);
      expect(g.requests, 0);
      expect(g.positions, 0);
    });

    test('tanpa prompt tetapi izin sudah ada: posisi diambil', () async {
      final g = FakeGateway(permission: GatewayPermission.granted);
      expect((await LocationService(g).locate(prompt: false)).ok, isTrue);
    });

    test('gagal/timeout mengambil posisi -> unavailable, tidak melempar', () async {
      final g = FakeGateway(permission: GatewayPermission.granted, positionError: Exception('timeout'));
      expect((await LocationService(g).locate()).status, LocationStatus.unavailable);
    });

    test('openSettingsFor: izin permanen -> pengaturan aplikasi; layanan mati -> pengaturan lokasi; lainnya tidak membuka', () async {
      final g = FakeGateway();
      final s = LocationService(g);
      expect(await s.openSettingsFor(LocationStatus.deniedForever), isTrue);
      expect(await s.openSettingsFor(LocationStatus.serviceOff), isTrue);
      expect(await s.openSettingsFor(LocationStatus.denied), isFalse);
      expect([g.appSettingsOpened, g.locationSettingsOpened], [1, 1]);
    });

    test('setiap status bermasalah punya pesan dan label aksi', () {
      for (final st in LocationStatus.values.where((x) => x != LocationStatus.granted)) {
        expect(locationStatusMessage(st), isNotEmpty, reason: '$st');
        expect(locationActionLabel(st), isNotEmpty, reason: '$st');
      }
      expect(locationStatusMessage(LocationStatus.deniedForever), contains('pengaturan'));
      expect(locationActionLabel(LocationStatus.deniedForever), 'Buka pengaturan');
    });
  });

  group('distanceKm (sama dengan backend)', () {
    test('Jakarta - Bandung sekitar 121 km; titik sama 0', () {
      expect(distanceKm(-6.2, 106.8, -6.9175, 107.6191), closeTo(121, 1.5));
      expect(distanceKm(-6.2, 106.8, -6.2, 106.8), 0);
    });
    test('nilai acuan dari uji backend: (-6.2,106.8) -> (-6.205,106.82) antara 2 dan 3 km', () {
      final d = distanceKm(-6.2, 106.8, -6.205, 106.82);
      expect(d, inExclusiveRange(2.0, 3.0));
    });
  });

  group('Geocoder (Nominatim)', () {
    const body = '[{"lat":"-6.2087634","lon":"106.845599","display_name":"Jakarta, Indonesia"},'
        '{"lat":"abc","lon":"1","display_name":"rusak"},{"lat":"1","lon":"2"}]';

    test('mengirim User-Agent yang jelas dan parameter pencarian; memilih hasil valid saja', () async {
      late http.Request seen;
      final g = Geocoder(
        client: MockClient((r) async {
          seen = r;
          return http.Response(body, 200);
        }),
        sleep: (_) async {},
      );
      final r = await g.search('  Jakarta ');
      expect(seen.url.host, 'nominatim.openstreetmap.org');
      expect(seen.url.queryParameters['q'], 'jakarta');
      expect(seen.url.queryParameters['format'], 'jsonv2');
      expect(seen.headers['User-Agent'], Geocoder.userAgent);
      expect(Geocoder.userAgent, contains('Code2Ticket'));
      expect(r, hasLength(1));
      expect([r.single.name, r.single.lat, r.single.lng], ['Jakarta, Indonesia', -6.2087634, 106.845599]);
    });

    test('hasil di-cache: pencarian sama (beda huruf/spasi) tidak memanggil server lagi', () async {
      var calls = 0;
      final g = Geocoder(client: MockClient((r) async => http.Response(++calls > 0 ? body : '', 200)), sleep: (_) async {});
      await g.search('Jakarta');
      await g.search('  JAKARTA ');
      expect(calls, 1);
    });

    test('kurang dari 3 huruf tidak memanggil server', () async {
      var calls = 0;
      final g = Geocoder(client: MockClient((r) async => http.Response(++calls > 0 ? '[]' : '', 200)), sleep: (_) async {});
      expect(await g.search('ja'), isEmpty);
      expect(calls, 0);
    });

    test('maksimal 1 permintaan per detik: permintaan beruntun diberi jeda', () async {
      var now = DateTime(2026, 1, 1, 12);
      final sleeps = <Duration>[];
      final stamps = <DateTime>[];
      final g = Geocoder(
        client: MockClient((r) async {
          stamps.add(now);
          return http.Response('[]', 200);
        }),
        clock: () => now,
        sleep: (d) async {
          sleeps.add(d);
          now = now.add(d);
        },
      );
      await Future.wait([g.search('aaa'), g.search('bbb'), g.search('ccc')]);
      expect(stamps, hasLength(3));
      expect(stamps[1].difference(stamps[0]), greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(stamps[2].difference(stamps[1]), greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(sleeps, hasLength(2));
    });

    test('429 / gagal jaringan / respons rusak -> NetworkException dengan pesan; tidak di-cache', () async {
      var mode = 429;
      var calls = 0;
      final g = Geocoder(
        client: MockClient((r) async {
          calls++;
          if (mode == 0) throw http.ClientException('putus');
          return http.Response(mode == 200 ? '{bukan json' : '', mode);
        }),
        sleep: (_) async {},
      );
      await expectLater(g.search('abc'), throwsA(isA<NetworkException>().having((e) => e.message, 'pesan', contains('dibatasi'))));
      mode = 0;
      await expectLater(g.search('abc'), throwsA(isA<NetworkException>()));
      mode = 200;
      await expectLater(g.search('abc'), throwsA(isA<NetworkException>()));
      expect(calls, 3); // kegagalan tidak masuk cache
    });
  });
}
