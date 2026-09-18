import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Default server port
  static const int port = 3000;

  /// Custom override URL passed via --dart-define=SERVER_URL=http://...
  static const String _envUrl = String.fromEnvironment('SERVER_URL');

  /// Dynamic user-configurable Base URL
  static String? customBaseUrl;

  /// Resolved active base URL
  static String? _resolvedBaseUrl;

  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      return customBaseUrl!;
    }
    if (_envUrl.isNotEmpty) {
      return _envUrl;
    }
    if (_resolvedBaseUrl != null) {
      return _resolvedBaseUrl!;
    }

    if (kIsWeb) {
      return 'http://localhost:$port';
    }

    // Default to localhost:3000 (works on desktop, iOS, and physical Android with adb reverse)
    return 'http://localhost:$port';
  }

  static void setResolvedBaseUrl(String url) {
    _resolvedBaseUrl = url;
  }

  // Fallback candidate URLs to try when discovering the server on Android
  static List<String> get candidateUrls {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      return [customBaseUrl!];
    }
    if (_envUrl.isNotEmpty) {
      return [_envUrl];
    }
    if (kIsWeb) {
      return ['http://localhost:$port'];
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Physical device (via adb reverse / 127.0.0.1) and Emulator (10.0.2.2)
      return [
        'http://localhost:$port',
        'http://127.0.0.1:$port',
        'http://10.0.2.2:$port',
      ];
    }
    return [
      'http://localhost:$port',
      'http://127.0.0.1:$port',
    ];
  }

  // Endpoints
  static Uri get partiesUri => Uri.parse('$baseUrl/api/parties');
  static Uri partyDetailUri(String id) => Uri.parse('$baseUrl/api/parties/$id');
  static Uri partyEntriesUri(String id) =>
      Uri.parse('$baseUrl/api/parties/$id/entries');
  static Uri get entriesUri => Uri.parse('$baseUrl/api/entries');
  static Uri entryDetailUri(String id) => Uri.parse('$baseUrl/api/entries/$id');
  static Uri get summaryUri => Uri.parse('$baseUrl/api/summary');
}
