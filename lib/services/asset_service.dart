import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class AssetService {
  AssetService._();
  static final AssetService instance = AssetService._();

  bool _initialized = false;
  final Map<String, String> _symbolIndex =
      {}; // key: basename (lowercase), value: full asset path

  Future<void> init() async {
    if (_initialized) return;
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestJson);
    const prefix = 'assets/mulberry-symbols/EN-symbols/';
    for (final path in manifest.keys) {
      if (path is String && path.startsWith(prefix) && path.endsWith('.svg')) {
        final name = path
            .substring(prefix.length, path.length - 4)
            .toLowerCase(); // drop ".svg"
        _symbolIndex[name] = path;
      }
    }
    _initialized = true;
  }

  // Try exact phrase -> token fallback, normalize to match filenames.
  String? lookup(String text) {
    if (!_initialized) return null;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .trim()
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(
          RegExp(r'^_|_$'),
          '',
        ); // Remove leading/trailing underscores

    final n = norm(text);
    if (n.isEmpty) return null;

    // 1. Try EXACT match first (most important!)
    if (_symbolIndex.containsKey(n)) {
      return _symbolIndex[n];
    }

    // 2. Try with underscores replaced by spaces
    final withSpaces = n.replaceAll('_', ' ');
    if (_symbolIndex.containsKey(withSpaces)) {
      return _symbolIndex[withSpaces];
    }

    // 3. Try individual words ONLY if no exact match
    final words = n
        .split('_')
        .where((w) => w.isNotEmpty && w.length > 2)
        .toList();
    for (final word in words) {
      if (_symbolIndex.containsKey(word)) {
        return _symbolIndex[word];
      }
    }

    return null;
  }

  // Add this static method
  static Future<List<String>> listSymbolFilenames() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    return manifestMap.keys
        .where(
          (path) =>
              path.startsWith('assets/mulberry-symbols/EN-symbols/') &&
              path.endsWith('.svg'),
        )
        .map((path) => path.split('/').last)
        .toList();
  }
}
