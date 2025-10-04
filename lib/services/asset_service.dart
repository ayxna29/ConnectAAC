import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// AssetService loads available symbol filenames from the AssetManifest at runtime
/// so we don't need to maintain a static hard-coded list.
class AssetService {
  static const String _symbolDir = 'assets/mulberry-symbols/EN-symbols/';
  static List<String>? _cached;

  /// Returns list of filenames (e.g. 'dog.svg') inside the symbol directory.
  static Future<List<String>> listSymbolFilenames() async {
    if (_cached != null) return _cached!;
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestJson);
    final files = <String>[];
    for (final assetPath in manifest.keys) {
      if (assetPath.startsWith(_symbolDir) && assetPath.endsWith('.svg')) {
        files.add(assetPath.substring(_symbolDir.length));
      }
    }
    files.sort();
    _cached = files;
    return files;
  }
}
