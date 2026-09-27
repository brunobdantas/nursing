final class ApiConfig {
  const ApiConfig._();

  /// Optional dynamic FastAPI origin for controlled deployments.
  ///
  /// The release build intentionally has no emulator/local default. A physical
  /// device must never depend on 10.0.2.2 or localhost.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Public, HTTPS clinical release used as the production bootstrap/fallback.
  static const String publicClinicalReleaseUrl = String.fromEnvironment(
    'CLINICAL_RELEASE_URL',
    defaultValue:
        'https://raw.githubusercontent.com/brunobdantas/nursing/main/'
        'clinical-releases/clinical-release-v1.json',
  );

  static Uri? get apiBaseUri {
    final value = apiBaseUrl.trim();
    return value.isEmpty ? null : Uri.tryParse(value);
  }

  static Uri get publicClinicalReleaseUri =>
      Uri.parse(publicClinicalReleaseUrl);
}
