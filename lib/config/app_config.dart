/// Compile-time application configuration for CareAgent.
class AppConfig {
  /// Creates immutable app configuration.
  const AppConfig({required this.apiBaseUrl});

  /// Reads config passed through `--dart-define`.
  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'CAREAGENT_API_BASE_URL',
      defaultValue: '',
    );
    return AppConfig(apiBaseUrl: apiBaseUrl);
  }

  /// Render backend base URL, without a trailing slash.
  final String apiBaseUrl;

  /// Whether backend API calls are enabled for this build.
  bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;
}
