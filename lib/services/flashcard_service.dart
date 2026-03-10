import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'asset_service.dart';

String? normalizeAssetFilename(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll('\\', '/').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.split('/').last;
}

/// Simple model for generated flashcards consumed by UI
class GeneratedFlashcard {
  final String id;
  final String question;
  final String answer;
  final List<String> tags;
  final String? assetFilename;
  final String? fitz; // ✅ Fitzgerald Key category from backend
  GeneratedFlashcard({
    required this.id,
    required this.question,
    required this.answer,
    required this.tags,
    this.assetFilename,
    this.fitz,
  });
}

class FavoriteCard {
  final String id;
  final String question;
  final String answer;
  final String assetFilename;

  FavoriteCard({
    required this.id,
    required this.question,
    required this.answer,
    required this.assetFilename,
  });

  factory FavoriteCard.fromJson(Map<String, dynamic> json) {
    return FavoriteCard(
      id: (json['id'] ?? '').toString(),
      question: (json['question'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
      assetFilename:
          normalizeAssetFilename(json['asset_filename']?.toString()) ??
          'blank.svg',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'asset_filename': assetFilename,
    };
  }
}

class FlashcardService {
  FlashcardService({
    this.backendBaseUrl = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'https://connectaac.onrender.com',
    ),
  });

  final String backendBaseUrl;
  final _supabase = Supabase.instance.client;
  String? _lastGenerationId;
  List<String>? _availableSymbolsCache;
  final List<String> _recentAnswers = [];

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

  Future<List<GeneratedFlashcard>> generate({
    required String caregiverInput,
    List<String>? explicitTags,
    bool adaptive = true,
    bool inferTags = true,
  }) async {
    await _ensureSymbols();
    final session = _supabase.auth.currentSession;
    final jwt = session?.accessToken;

    final List<String>? tagsForRequest =
        (explicitTags != null && explicitTags.isNotEmpty) ? explicitTags : null;

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
        'tags': tagsForRequest.take(12).toList(),
      if (_lastGenerationId != null) 'avoid_generation_id': _lastGenerationId,
    };

    final resp = await http.post(
      Uri.parse('$backendBaseUrl/generate_flashcards'),
      headers: {
        'Authorization': 'Bearer ${jwt ?? ''}',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );
    print('🔗 Backend response: statusCode=${resp.statusCode}');
    if (resp.statusCode == 0) {
      throw Exception('No response (network/CORS)');
    }
    if (resp.statusCode != 200) {
      print('❌ Backend error: ${resp.body}');
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final Map<String, dynamic> decoded =
        json.decode(resp.body) as Map<String, dynamic>;
    final genId = decoded['generation_id']?.toString();
    if (genId != null && genId.isNotEmpty) {
      _lastGenerationId = genId;
    }
    final List<dynamic> list = decoded['flashcards'] as List<dynamic>? ?? [];
    print('📊 Parsed ${list.length} flashcards from response');
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
            assetFilename: normalizeAssetFilename(
              m['asset_filename']?.toString(),
            ),
            fitz: m['fitz']?.toString(), // ✅ read fitz from backend response
          );
        })
        .where((c) => c.answer.isNotEmpty)
        .toList();

    for (final c in cards) {
      final ans = c.answer.trim();
      if (ans.isEmpty) continue;
      _recentAnswers.removeWhere((w) => w.toLowerCase() == ans.toLowerCase());
      _recentAnswers.insert(0, ans);
    }
    if (_recentAnswers.length > 60) {
      _recentAnswers.removeRange(60, _recentAnswers.length);
    }

    return cards;
  }

  Future<List<String>> fetchUserTags() async {
    try {
      final res = await _supabase
          .from('user_tags')
          .select('tag_name')
          .order('created_at', ascending: true);
      final rows = (res as List<dynamic>?) ?? <dynamic>[];
      return rows
          .whereType<Map>()
          .map((r) => (r['tag_name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return <String>[];
    }
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
        final direct = _directMatch(head, pool);
        if (direct != null) return direct;
      }
    }
    return null;
  }

  String? _fuzzyMatch(String word, List<String> pool) {
    int bestDist = 10;
    String? best;
    for (final f in pool) {
      final base = f.toLowerCase().replaceAll('.svg', '');
      final dist = _levenshtein(word, base);
      if (dist < bestDist) {
        bestDist = dist;
        best = f;
      }
    }
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
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[m][n];
  }

  Future<List<GeneratedFlashcard>> generateFlashcards({
    required String backendBaseUrl,
    required String context,
    required List<String> explicitTags,
    String? avoidGenerationId,
    bool lite = false,
  }) async {
    await _loadAssetIndex();
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not signed in');

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
    final list = (jsonResp['flashcards'] as List?) ?? [];
    final out = <GeneratedFlashcard>[];

    for (final f in list) {
      if (f is! Map) continue;
      final q = f['question']?.toString() ?? '';
      final a = f['answer']?.toString() ?? '';
      if (q.isEmpty || a.isEmpty) continue;

      final cleaned = a.replaceAll(RegExp(r"[^\w\s']"), '');
      final tokens = cleaned.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      final stopwords = <String>{
        'i',"i'm",'im','am','are','you','we','they','he','she','it',
        'what','why','how','when','where','the','a','an','to','do',
        'does','please','would','like','want','wanting','could','should',
      };
      String keyWord = '';
      for (final t in tokens) {
        final low = t.toLowerCase();
        if (low.length > 2 && !stopwords.contains(low)) {
          keyWord = low;
          break;
        }
      }
      if (keyWord.isEmpty) {
        keyWord = tokens.isNotEmpty ? tokens.last.toLowerCase() : a.toLowerCase();
      }
      final asset = _matchAsset(keyWord);
      out.add(GeneratedFlashcard(
        id: (f['id'] ?? '').toString(),
        question: q,
        answer: a,
        tags: (f['tags'] is List)
            ? (f['tags'] as List).map((t) => t.toString()).toList()
            : <String>[],
        assetFilename: asset,
        fitz: f['fitz']?.toString(), // ✅ read fitz here too
      ));
    }
    return out;
  }

  String? _matchAsset(String word) {
    if (_availableSymbolsCache == null || _availableSymbolsCache!.isEmpty) return null;
    final normalized = word.toLowerCase().trim();
    final direct = _directMatch(normalized, _availableSymbolsCache!);
    return direct ??
        _synonymMatch(normalized, _availableSymbolsCache!) ??
        _fuzzyMatch(normalized, _availableSymbolsCache!);
  }

  Future<void> _loadAssetIndex() async {
    final base = backendBaseUrl;
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not signed in (session null)');

    _availableSymbolsCache ??= <String>[];

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
    final Map<String, dynamic> jsonResp =
        json.decode(resp.body) as Map<String, dynamic>;
    final List<dynamic> list = (jsonResp['files'] as List?) ?? <dynamic>[];
    final seen = <String>{};
    for (final f in list) {
      if (f is! Map) continue;
      final path = f['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      if (!(path.startsWith('assets/en-symbols/') ||
          path.startsWith('assets/mulberry-symbols/EN-symbols/') ||
          path.contains('/en-symbols/') ||
          path.contains('/EN-symbols/'))) continue;

      final normalized = path.replaceAll('\\', '/').split('/').last;
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      _availableSymbolsCache!.add(normalized);
    }
  }

  Future<List<FavoriteCard>> fetchFavorites() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not signed in');
    final r = await http.get(
      Uri.parse('$backendBaseUrl/flashcards/favorites'),
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );
    if (r.statusCode != 200) throw Exception('Favorites fetch ${r.statusCode}');
    final body = json.decode(r.body);
    final List<dynamic> list = (body is Map && body['favorites'] is List)
        ? (body['favorites'] as List)
        : <dynamic>[];
    return list
        .map((e) {
          final m = (e is Map) ? Map<String, dynamic>.from(e) : <String, dynamic>{};
          return FavoriteCard.fromJson(m);
        })
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  Future<void> favoriteCard(String cardId) async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not signed in');
    final response = await http.post(
      Uri.parse('$backendBaseUrl/flashcards/$cardId/favorite'),
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to favorite: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> unfavoriteCard(String cardId) async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not signed in');
    final response = await http.delete(
      Uri.parse('$backendBaseUrl/flashcards/$cardId/favorite'),
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unfavorite: ${response.statusCode} ${response.body}');
    }
  }
}