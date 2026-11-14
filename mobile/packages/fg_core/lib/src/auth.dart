import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';
import 'oidc.dart';
import 'outbox.dart';
import 'server_check.dart';

const _tokenKey = 'fg.token';
const _serverKey = 'fg.server';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// Restores the server address chosen on the phone. Call once in main() before runApp.
Future<void> loadSavedServer() async {
  try {
    final saved = await const FlutterSecureStorage().read(key: _serverKey);
    if (saved != null && saved.isNotEmpty) FgConfig.setApiOverride(saved);
  } catch (_) {
    // no saved address (or the store is unavailable): the build-time address is used
  }
}

/// The Fleet Geeks server address in use; changing it rebuilds the API client.
class ServerAddressNotifier extends Notifier<String> {
  @override
  String build() => FgConfig.apiBase;

  /// Saves the address on the phone (empty = back to the build-time address).
  Future<void> set(String value) async {
    final v = FgConfig.normalizeApiBase(value);
    final storage = ref.read(secureStorageProvider);
    if (v.isEmpty || v == FgConfig.buildApiBase) {
      await storage.delete(key: _serverKey);
    } else {
      await storage.write(key: _serverKey, value: v);
    }
    FgConfig.setApiOverride(v == FgConfig.buildApiBase ? '' : v);
    state = FgConfig.apiBase;
  }

  /// D-113: checks the typed address (API address or portal link, same Wi-Fi or published), then saves the API it leads
  /// to. Throws [ServerCheckException] and keeps the current server when the address does not lead to Fleet Geeks.
  Future<ServerCheck> connect(String value) async {
    final found = await checkServer(value);
    await set(found.apiBase);
    return found;
  }
}

final serverAddressProvider = NotifierProvider<ServerAddressNotifier, String>(ServerAddressNotifier.new);

/// D-110: OpenID Connect session (production sign-in).
final oidcProvider = Provider<FgOidc>((ref) => FgOidc(ref.watch(secureStorageProvider)));

/// The API client used by every screen. The token lives in the platform secure storage (Android Keystore).
final apiProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(
    baseUrl: ref.watch(serverAddressProvider),
    // D-110: with OIDC the access token is refreshed silently before it expires
    tokenProvider: () => FgOidc.configured ? ref.read(oidcProvider).validToken() : storage.read(key: _tokenKey),
    // an expired session keeps the user's queued commands (sent after the same user signs in again)
    onUnauthorized: () => ref.read(authProvider.notifier).signOut(wipe: false),
  );
});

/// Signed-in portal user; null when signed out. D365 decides the user's scope, never the app.
class AuthNotifier extends AsyncNotifier<PortalUser?> {
  @override
  Future<PortalUser?> build() async {
    final token = await ref.read(secureStorageProvider).read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    try {
      return PortalUser.fromJson(Map<String, dynamic>.from(await ref.read(apiProvider).get('/me') as Map));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await ref.read(secureStorageProvider).delete(key: _tokenKey);
        return null;
      }
      rethrow;
    }
  }

  /// Development sign-in (the API offers it only in its Development environment).
  Future<void> signInDev(String portalUserId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiProvider);
      final res = Map<String, dynamic>.from(await api.post('/dev/token', body: {'portalUserId': portalUserId}) as Map);
      await ref.read(secureStorageProvider).write(key: _tokenKey, value: '${res['access_token']}');
      return PortalUser.fromJson(Map<String, dynamic>.from(await api.get('/me') as Map));
    });
  }

  /// Production sign-in: the token from the organisation's OpenID Connect provider (see README, blocker B-01).
  Future<void> signInWithToken(String accessToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(secureStorageProvider).write(key: _tokenKey, value: accessToken);
      return PortalUser.fromJson(Map<String, dynamic>.from(await ref.read(apiProvider).get('/me') as Map));
    });
  }

  /// D-110: production sign-in through the OpenID Connect provider (system browser, PKCE).
  Future<void> signInOidc() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(oidcProvider).signIn();
      return PortalUser.fromJson(Map<String, dynamic>.from(await ref.read(apiProvider).get('/me') as Map));
    });
  }

  /// Sign-out. A deliberate sign-out wipes the offline queue and its key (D-109) and ends the provider session (D-110);
  /// an expired session does not wipe the queue.
  Future<void> signOut({bool wipe = true}) async {
    if (wipe) await ref.read(outboxProvider.notifier).wipe();
    if (wipe && FgOidc.configured) await ref.read(oidcProvider).signOut();
    await ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, PortalUser?>(AuthNotifier.new);
