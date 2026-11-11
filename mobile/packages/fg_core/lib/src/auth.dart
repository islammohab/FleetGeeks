import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';

const _tokenKey = 'fg.token';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// The API client used by every screen. The token lives in the platform secure storage (Android Keystore).
final apiProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(
    baseUrl: FgConfig.apiBase,
    tokenProvider: () => storage.read(key: _tokenKey),
    onUnauthorized: () => ref.read(authProvider.notifier).signOut(),
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

  Future<void> signOut() async {
    await ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, PortalUser?>(AuthNotifier.new);
