import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// D-113: a checked Fleet Geeks server - the API base the app uses and what the API reported.
class ServerCheck {
  const ServerCheck({required this.apiBase, required this.company, required this.signIn});

  /// API base URL the app calls (`<apiBase>/api/v1/...`).
  final String apiBase;

  /// D365 company the API works in (for example USMF).
  final String company;

  /// `development` (pick a portal user) or `oidc` (organisation sign-in).
  final String signIn;
}

/// Why an address is not a usable Fleet Geeks server: `empty`, `unreachable` (no answer at all - wrong address, other
/// network, firewall) or `notFleetGeeks` (something answers, but no Fleet Geeks API behind it).
class ServerCheckException implements Exception {
  const ServerCheckException(this.reason);
  final String reason;

  @override
  String toString() => 'ServerCheckException($reason)';
}

/// D-113: accepts what the user types - the API address or a portal link, on the same Wi-Fi
/// (`http://192.168.1.20:5098` or `http://192.168.1.20:5174`) or published (`https://fleet.example.com`) - and finds the API:
/// 1. `<address>/api/v1/ping` answers: the address itself (the API, or a portal that forwards /api to the API);
/// 2. otherwise `<address>/fleetgeeks.json` names the API (a published portal built with another API address), whose ping
///    must answer.
Future<ServerCheck> checkServer(String address, {http.Client? client, Duration timeout = const Duration(seconds: 8)}) async {
  final base = FgConfig.normalizeApiBase(address);
  if (base.isEmpty) throw const ServerCheckException('empty');
  final c = client ?? http.Client();
  var answered = false;
  Future<Object?> getJson(String url) async {
    try {
      final r = await c.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(timeout);
      answered = true;
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      answered = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ServerCheck?> ping(String apiBase) async {
    final j = await getJson('$apiBase/api/v1/ping');
    if (j is Map && j['service'] == 'Fleet Geeks API') {
      return ServerCheck(apiBase: apiBase, company: '${j['company'] ?? ''}', signIn: '${j['signIn'] ?? ''}');
    }
    return null;
  }

  try {
    final direct = await ping(base);
    if (direct != null) return direct;
    final config = await getJson('$base/fleetgeeks.json');
    if (config is Map) {
      final named = '${config['api'] ?? ''}'.trim();
      final api = named.startsWith('/') ? '$base$named' : FgConfig.normalizeApiBase(named);
      if (api.isNotEmpty && api != base) {
        final viaPortal = await ping(FgConfig.normalizeApiBase(api));
        if (viaPortal != null) return viaPortal;
      }
    }
    throw ServerCheckException(answered ? 'notFleetGeeks' : 'unreachable');
  } finally {
    if (client == null) c.close();
  }
}
