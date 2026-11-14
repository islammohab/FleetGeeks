import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// D-110 (brief 28): production sign-in with the organisation's OpenID Connect provider (for example Entra External ID):
/// authorization code flow with PKCE in the system browser (never an embedded web view), the tokens in the platform
/// secure storage, a silent refresh before the access token expires, and the provider session ended on sign-out.
class FgOidc {
  FgOidc(this._storage, [FlutterAppAuth? appAuth]) : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterSecureStorage _storage;
  final FlutterAppAuth _appAuth;

  static const accessKey = 'fg.token';
  static const _refreshKey = 'fg.refresh';
  static const _idTokenKey = 'fg.idtoken';
  static const _expiresKey = 'fg.expires';

  /// Whether OIDC is configured for this build (FG_OIDC_ISSUER and FG_OIDC_CLIENT_ID).
  static bool get configured => FgConfig.oidcIssuer.isNotEmpty && FgConfig.oidcClientId.isNotEmpty;

  /// Interactive sign-in; returns the access token.
  Future<String> signIn() async {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        FgConfig.oidcClientId,
        FgConfig.oidcRedirect,
        issuer: FgConfig.oidcIssuer,
        scopes: FgConfig.oidcScopes.split(' ').where((s) => s.isNotEmpty).toList(),
        promptValues: const ['login'],
      ),
    );
    return _store(result.accessToken, result.refreshToken, result.idToken, result.accessTokenExpirationDateTime);
  }

  /// A valid access token: the stored one, or a refreshed one when it expires within two minutes; null when the session
  /// cannot be renewed (the user signs in again).
  Future<String?> validToken() async {
    final token = await _storage.read(key: accessKey);
    if (token == null || token.isEmpty) return null;
    final expires = DateTime.tryParse(await _storage.read(key: _expiresKey) ?? '');
    if (expires == null || expires.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)))) return token;
    return refresh();
  }

  /// Silent refresh with the refresh token; null when there is none or the provider refuses it.
  Future<String?> refresh() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    if (!configured || refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final result = await _appAuth.token(TokenRequest(
        FgConfig.oidcClientId,
        FgConfig.oidcRedirect,
        issuer: FgConfig.oidcIssuer,
        refreshToken: refreshToken,
        scopes: FgConfig.oidcScopes.split(' ').where((s) => s.isNotEmpty).toList(),
      ));
      return await _store(result.accessToken, result.refreshToken ?? refreshToken, result.idToken, result.accessTokenExpirationDateTime);
    } catch (_) {
      return null;
    }
  }

  /// Ends the provider session (best effort) and removes the tokens.
  Future<void> signOut() async {
    final idToken = await _storage.read(key: _idTokenKey);
    if (configured && idToken != null && idToken.isNotEmpty) {
      try {
        await _appAuth.endSession(EndSessionRequest(idTokenHint: idToken, postLogoutRedirectUrl: FgConfig.oidcRedirect, issuer: FgConfig.oidcIssuer));
      } catch (_) {
        // the local session ends regardless
      }
    }
    for (final key in [accessKey, _refreshKey, _idTokenKey, _expiresKey]) {
      await _storage.delete(key: key);
    }
  }

  Future<String> _store(String? access, String? refresh, String? idToken, DateTime? expires) async {
    if (access == null || access.isEmpty) throw StateError('The sign-in provider returned no access token.');
    await _storage.write(key: accessKey, value: access);
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
    if (idToken != null) await _storage.write(key: _idTokenKey, value: idToken);
    await _storage.write(key: _expiresKey, value: (expires ?? DateTime.now().add(const Duration(minutes: 50))).toUtc().toIso8601String());
    return access;
  }
}
