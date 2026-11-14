/// Build-time configuration (pass with --dart-define).
///
///   flutter build apk --dart-define=FG_API=https://api.example.com --dart-define=FG_DEV_SIGNIN=false
///
/// The Android emulator reaches the development API on the host machine through 10.0.2.2.
class FgConfig {
  const FgConfig._();

  /// Fleet Geeks API base URL given at build time (the apps never call D365 directly).
  static const String buildApiBase = String.fromEnvironment('FG_API', defaultValue: 'http://10.0.2.2:5098');

  /// Server address chosen on the phone (sign-in screen); empty = the build-time address.
  static String _apiOverride = '';

  /// The API base URL in use.
  static String get apiBase => _apiOverride.isNotEmpty ? _apiOverride : buildApiBase;

  /// Sets the server address chosen on the phone (empty = back to the build-time address).
  static void setApiOverride(String value) => _apiOverride = normalizeApiBase(value);

  /// Trims, adds http:// when no scheme is given and removes a trailing slash or /api/v1.
  static String normalizeApiBase(String value) {
    var v = value.trim();
    if (v.isEmpty) return '';
    if (!v.contains('://')) v = 'http://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    if (v.endsWith('/api/v1')) v = v.substring(0, v.length - '/api/v1'.length);
    return v;
  }

  /// Development sign-in with a demo portal user (the API accepts it only in its Development environment).
  static const bool devSignIn = bool.fromEnvironment('FG_DEV_SIGNIN', defaultValue: true);

  /// Environment label shown on the sign-in screen.
  static const String environment = String.fromEnvironment('FG_ENV', defaultValue: 'Development');

  /// D-110: OpenID Connect sign-in (production). Empty issuer = the OIDC button is not offered.
  static const String oidcIssuer = String.fromEnvironment('FG_OIDC_ISSUER');
  static const String oidcClientId = String.fromEnvironment('FG_OIDC_CLIENT_ID');
  /// Redirect URI registered with the provider; its scheme is the app's appAuthRedirectScheme (see README).
  static const String oidcRedirect = String.fromEnvironment('FG_OIDC_REDIRECT', defaultValue: 'com.fleetgeeks.app:/oauth2redirect');
  static const String oidcScopes = String.fromEnvironment('FG_OIDC_SCOPES', defaultValue: 'openid profile offline_access');
}
