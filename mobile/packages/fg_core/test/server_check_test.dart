// D-113: the app's server address accepts the API address or a portal link (same Wi-Fi or published).
import 'dart:convert';

import 'package:fg_core/fg_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _ping = '{"service":"Fleet Geeks API","company":"USMF","devSignIn":true,"signIn":"development"}';

void main() {
  test('an API address is used as it is (http://<PC>:5098 on the same Wi-Fi)', () async {
    final client = MockClient((r) async => r.url.path == '/api/v1/ping' ? http.Response(_ping, 200) : http.Response('', 404));
    final found = await checkServer('192.168.1.20:5098/', client: client);
    expect(found.apiBase, 'http://192.168.1.20:5098');
    expect(found.company, 'USMF');
  });

  test('a portal that forwards /api to the API is used as it is', () async {
    final client = MockClient((r) async => r.url.port == 5174 && r.url.path == '/api/v1/ping' ? http.Response(_ping, 200) : http.Response('', 404));
    final found = await checkServer('http://192.168.1.20:5174', client: client);
    expect(found.apiBase, 'http://192.168.1.20:5174');
  });

  test('a published portal names its API in fleetgeeks.json', () async {
    final client = MockClient((r) async {
      if (r.url.host == 'fleet.example.com' && r.url.path == '/fleetgeeks.json') return http.Response(jsonEncode({'api': 'https://api.example.com'}), 200);
      if (r.url.host == 'api.example.com' && r.url.path == '/api/v1/ping') return http.Response(_ping, 200);
      return http.Response('<html></html>', 404);
    });
    final found = await checkServer('https://fleet.example.com', client: client);
    expect(found.apiBase, 'https://api.example.com');
  });

  test('no answer at all = unreachable; an answer without Fleet Geeks = not Fleet Geeks; empty = empty', () async {
    final down = MockClient((r) async => throw http.ClientException('no route'));
    await expectLater(checkServer('http://10.0.0.9:5098', client: down), throwsA(isA<ServerCheckException>().having((e) => e.reason, 'reason', 'unreachable')));
    final other = MockClient((r) async => http.Response('<html>router</html>', 200));
    await expectLater(checkServer('http://192.168.1.1', client: other), throwsA(isA<ServerCheckException>().having((e) => e.reason, 'reason', 'notFleetGeeks')));
    await expectLater(checkServer('  ', client: other), throwsA(isA<ServerCheckException>().having((e) => e.reason, 'reason', 'empty')));
  });
}
