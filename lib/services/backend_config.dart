import 'package:flutter/foundation.dart' show kIsWeb;

class BackendConfig {
  static String resolve() {
    if (kIsWeb) {
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      return 'http://$host:5000';
    }
    return 'http://localhost:5000';
  }
}
