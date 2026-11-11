/// Build-time configuration (pass with --dart-define).
///
///   flutter build apk --dart-define=FG_API=https://api.example.com --dart-define=FG_DEV_SIGNIN=false
///
/// The Android emulator reaches the development API on the host machine through 10.0.2.2.
class FgConfig {
  const FgConfig._();

  /// Fleet Geeks API base URL (the apps never call D365 directly).
  static const String apiBase = String.fromEnvironment('FG_API', defaultValue: 'http://10.0.2.2:5098');

  /// Development sign-in with a demo portal user (the API accepts it only in its Development environment).
  static const bool devSignIn = bool.fromEnvironment('FG_DEV_SIGNIN', defaultValue: true);

  /// Environment label shown on the sign-in screen.
  static const String environment = String.fromEnvironment('FG_ENV', defaultValue: 'Development');
}
