import 'package:flutter/foundation.dart' show kIsWeb;

class BackendConfig {
  static String resolve() {
    if (kIsWeb) {
      // Prefer a compile-time `API_URL` so builds can target different backends.
      const String _envApi = String.fromEnvironment(
        'API_URL',
        defaultValue: 'https://connectaac.onrender.com',
      );
      return _envApi;
    }
    return 'http://localhost:5000';
  }
}
