import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

/// Change to 'http://localhost:5000' for desktop/emulator,
/// or your ngrok URL when testing on a physical device.
/// Use compile-time environment `API_URL` with a sensible default.
/// For local emulators override with `--dart-define=API_URL=http://localhost:5000` when building.
const String _apiBase = const String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://connectaac.onrender.com',
);

Future<List<Map<String, dynamic>>> generateFlashcardsFromAI(
  String context, {
  String answerLength = 'mixed',
  bool adaptive = true,
  bool inferTags = true,
  List<String>? tags,
  String? avoidGenerationId,
}) async {
  final session = _supabase.auth.currentSession;
  final jwt = session?.accessToken;
  final body = <String, dynamic>{
    'context': context,
    'answer_length': answerLength,
    'adaptive': adaptive,
    'infer_tags': inferTags,
    if (tags != null && tags.isNotEmpty) 'tags': tags,
    if (avoidGenerationId != null) 'avoid_generation_id': avoidGenerationId,
    'reuse': false,
  };
  final resp = await http.post(
    Uri.parse('$_apiBase/generate_flashcards'),
    headers: {
      'Content-Type': 'application/json',
      if (jwt != null) 'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode(body),
  );
  if (resp.statusCode != 200) {
    throw Exception('AI server error ${resp.statusCode}: ${resp.body}');
  }
  final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
  final list = (decoded['flashcards'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  return list;
}

Future<void> sendFlashcardFeedback({
  required String cardId,
  required int rating,
  bool edited = false,
  String? notes,
}) async {
  final session = _supabase.auth.currentSession;
  final jwt = session?.accessToken;
  if (jwt == null) throw Exception('Not signed in');
  final resp = await http.post(
    Uri.parse('$_apiBase/flashcards/feedback'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({
      'card_id': cardId,
      'rating': rating,
      'edited': edited,
      'notes': notes,
    }),
  );
  if (resp.statusCode != 200) {
    throw Exception('Feedback error ${resp.statusCode}: ${resp.body}');
  }
}
