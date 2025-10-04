import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'asset_service.dart';
import 'backend_config.dart';

/// Simple model for generated flashcards consumed by UI
class GeneratedFlashcard {
  final String id;
  final String question;
  final String answer; // treated as the display word/phrase
  final List<String> tags;
  final String? assetFilename; // matched symbol filename (e.g. dog.svg)
  GeneratedFlashcard({
    required this.id,
    required this.question,
    required this.answer,
    required this.tags,
    this.assetFilename,
  });
}

class FlashcardService {
  FlashcardService({this.backendBaseUrl = 'http://localhost:5000'});

  final String backendBaseUrl;
  final _supabase = Supabase.instance.client;
  String? _lastGenerationId; // track to avoid duplicates in next call
  List<String>? _availableSymbolsCache;
  final List<String> _recentAnswers =
      []; // rolling memory to personalize context

  // A lightweight synonym/normalization map to improve symbol matching.
  static const Map<String, List<String>> _synonyms = {
    'airplane': ['aeroplane', 'plane', 'jet', 'aircraft'],
    'car': ['auto', 'automobile', 'vehicle'],
    'bicycle': ['bike', 'cycle'],
    'dog': ['puppy', 'hound', 'canine'],
  };

  Future<void> _ensureSymbols() async {
    if (_availableSymbolsCache != null) return;
    _availableSymbolsCache = await AssetService.listSymbolFilenames();
  }

  /// Generate 15 flashcards from backend given caregiver context.
  /// - Prefers short & medium answers (mixed distribution handled server-side)
  /// - Avoids previous generation's IDs for novelty
  /// - Optionally merges favorites (caller can handle UI ordering)
  Future<List<GeneratedFlashcard>> generate({
    required String caregiverInput,
    List<String>? explicitTags,
    bool adaptive = true,
    bool inferTags = true,
  }) async {
    await _ensureSymbols();
    final session = _supabase.auth.currentSession;
    final jwt = session?.accessToken;

    // If caller did not provide tags, pull user's tag vocabulary from DB
    List<String>? tagsForRequest = explicitTags;
    if (tagsForRequest == null || tagsForRequest.isEmpty) {
      try {
        final tagRes = await _supabase.from('tags').select('name');
        final rows = tagRes as List<dynamic>? ?? [];
        tagsForRequest = rows
            .whereType<Map>()
            .map((r) => r['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {
        // ignore if tags cannot be fetched
      }
    }

    // Build adaptive context including last successful answers (vocabulary memory)
    String adaptiveContext = caregiverInput.trim();
    if (_recentAnswers.isNotEmpty) {
      final recentSlice = _recentAnswers.take(20).join(', ');
      adaptiveContext +=
          '\nPrevious relevant vocabulary (avoid duplicates, build on these if helpful): ' +
          recentSlice;
    }

    final body = <String, dynamic>{
      'context': adaptiveContext,
      'answer_length': 'mixed',
      'adaptive': adaptive,
      'infer_tags': inferTags,
      'reuse': false,
      if (tagsForRequest != null && tagsForRequest.isNotEmpty)
        'tags': tagsForRequest.take(12).toList(), // cap to keep prompt concise
      if (_lastGenerationId != null) 'avoid_generation_id': _lastGenerationId,
    };

    final resp = await http.post(
      Uri.parse('$backendBaseUrl/generate_flashcards'),
      headers: {
        'Authorization': 'Bearer ${session?.accessToken ?? ''}',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );
    if (resp.statusCode == 0) {
      throw Exception('No response (network/CORS)');
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final genId = decoded['generation_id']?.toString();
    if (genId != null && genId.isNotEmpty) {
      _lastGenerationId = genId; // store for next avoidance
    }
    final List<dynamic> list = decoded['flashcards'] as List<dynamic>? ?? [];
    final cards = list
        .map((e) {
          final m = e as Map<String, dynamic>;
          return GeneratedFlashcard(
            id: m['id']?.toString() ?? '',
            question: m['question']?.toString() ?? '',
            answer: m['answer']?.toString() ?? (m['text']?.toString() ?? ''),
            tags: (m['tags'] as List<dynamic>? ?? [])
                .map((t) => t.toString())
                .toList(),
          );
        })
        .where((c) => c.answer.isNotEmpty)
        .toList();

    // Update rolling memory (most recent first, maintain uniqueness & cap)
    for (final c in cards) {
      final ans = c.answer.trim();
      if (ans.isEmpty) continue;
      // prevent duplicates: move to front if already exists
      _recentAnswers.removeWhere((w) => w.toLowerCase() == ans.toLowerCase());
      _recentAnswers.insert(0, ans);
    }
    if (_recentAnswers.length > 60) {
      _recentAnswers.removeRange(60, _recentAnswers.length);
    }

    // Map answers to assets
    return _mapAssets(cards);
  }

  List<GeneratedFlashcard> _mapAssets(List<GeneratedFlashcard> cards) {
    final pool = _availableSymbolsCache ?? const <String>[];
    if (pool.isEmpty) return cards; // nothing to map

    return cards.map((c) {
      final normalized = c.answer.toLowerCase().trim();
      final direct = _directMatch(normalized, pool);
      final chosen =
          direct ??
          _synonymMatch(normalized, pool) ??
          _fuzzyMatch(normalized, pool);
      return GeneratedFlashcard(
        id: c.id,
        question: c.question,
        answer: c.answer,
        tags: c.tags,
        assetFilename: chosen,
      );
    }).toList();
  }

  String? _directMatch(String word, List<String> pool) {
    final variants = <String>{word};
    if (word.endsWith('s')) variants.add(word.substring(0, word.length - 1));
    if (word.endsWith('es')) variants.add(word.substring(0, word.length - 2));
    for (final v in variants) {
      final hit = pool.firstWhere(
        (f) =>
            f.toLowerCase() == '$v.svg' ||
            f.toLowerCase().replaceAll('.svg', '') == v,
        orElse: () => '',
      );
      if (hit.isNotEmpty) return hit;
    }
    return null;
  }

  String? _synonymMatch(String word, List<String> pool) {
    for (final entry in _synonyms.entries) {
      final head = entry.key;
      final all = [entry.key, ...entry.value];
      if (all.contains(word)) {
        // try each variant for the head symbol
        final direct = _directMatch(head, pool);
        if (direct != null) return direct;
      }
    }
    return null;
  }

  String? _fuzzyMatch(String word, List<String> pool) {
    int bestDist = 10; // cap distance search
    String? best;
    for (final f in pool) {
      final base = f.toLowerCase().replaceAll('.svg', '');
      final dist = _levenshtein(word, base);
      if (dist < bestDist) {
        bestDist = dist;
        best = f;
      }
    }
    // Accept only reasonably close matches (distance <= 2 or small words tolerance)
    if (bestDist <= 2 || (word.length <= 5 && bestDist <= 3)) return best;
    return null;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) dp[i][0] = i;
    for (var j = 0; j <= n; j++) dp[0][j] = j;
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }
    return dp[m][n];
  }

  // Add a simple generate wrapper so home.dart call matches:
  // Modify generateFlashcards signature & endpoint:
  Future<List<GeneratedFlashcard>> generateFlashcards({
    required String backendBaseUrl,
    required String context,
    required List<String> explicitTags,
    String? avoidGenerationId,
    bool lite = false,
  }) async {
    await _loadAssetIndex();
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Not signed in');
    }

    final uri = Uri.parse(
      '$backendBaseUrl/generate_flashcards${lite ? '?lite=1' : ''}',
    );

    final body = {
      'context': context,
      'answer_length': 'mixed',
      'adaptive': true,
      'reuse': false,
      'infer_tags': true,
      if (explicitTags.isNotEmpty) 'tags': explicitTags,
      if (avoidGenerationId != null) 'avoid_generation_id': avoidGenerationId,
      if (lite) 'lite': true,
    };

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final jsonResp = json.decode(resp.body);
    final genId = jsonResp['generation_id']?.toString() ?? '';
    final list = (jsonResp['flashcards'] as List?) ?? [];
    final out = <GeneratedFlashcard>[];

    for (final f in list) {
      if (f is! Map) continue;
      final q = f['question']?.toString() ?? '';
      final a = f['answer']?.toString() ?? '';
      if (q.isEmpty || a.isEmpty) continue;
      final keyWord = a.split(RegExp(r'\s+')).first;
      final asset = _matchAsset(keyWord);
      out.add(GeneratedFlashcard(
        id: (f['id'] ?? '').toString(),
        question: q,
        answer: a,
        tags: (f['tags'] is List) ? (f['tags'] as List).map((t) => t.toString()).toList() : <String>[],
        assetFilename: asset,
      ));
    }
    return out;
  }

  String? _matchAsset(String word) {
    if (_availableSymbolsCache == null || _availableSymbolsCache!.isEmpty) return null;
    final normalized = word.toLowerCase().trim();
    final direct = _directMatch(normalized, _availableSymbolsCache!);
    final chosen =
        direct ??
        _synonymMatch(normalized, _availableSymbolsCache!) ??
        _fuzzyMatch(normalized, _availableSymbolsCache!);
    return chosen;
  }

  Future<void> _loadAssetIndex() async {
    final base = 'http://localhost:5000';
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw Exception('Not signed in (session null)');
    }

    final jwt = session.accessToken;
    final uri = Uri.parse('$base/list_assets');
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final jsonResp = json.decode(resp.body);
    final List<dynamic> list = jsonResp['files'] ?? [];
    final seen = <String>{}; // de-duplication set
    for (final f in list) {
      if (f is! Map) continue;
      final path = f['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      // inside _loadAssetIndex for-loop condition change:
      if (!(path.startsWith('assets/en-symbols/') ||
          path.startsWith('assets/mulberry-symbols/EN-symbols/') ||
          path.contains('/en-symbols/') ||
          path.contains('/EN-symbols/')))
        continue;
      // Normalize & filter duplicates
      final normalized = path
          .replaceAll('\\', '/')
          .replaceAll('assets/en-symbols/', '')
          .replaceAll('assets/mulberry-symbols/EN-symbols/', '');
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      // Add both original and normalized paths for flexibility
      _availableSymbolsCache?.add(normalized);
      _availableSymbolsCache?.add(path);
    }
  }
}
