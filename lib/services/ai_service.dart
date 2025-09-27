import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

/// Change to 'http://localhost:5000' for desktop/emulator,
/// or your ngrok URL when testing on a physical device.
const String _apiBase = 'http://localhost:5000';

Future<List<Map<String, dynamic>>> generateFlashcardsFromAI(
  String context, {
  String? tag,
}) async {
  final session = _supabase.auth.currentSession;
  final jwt = session?.accessToken;
  final resp = await http.post(
    Uri.parse('$_apiBase/api/generate_flashcards'),
    headers: {
      'Content-Type': 'application/json',
      if (jwt != null) 'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode({'context': context, 'tag': tag}),
  );

  if (resp.statusCode != 200) {
    throw Exception('AI server error ${resp.statusCode}: ${resp.body}');
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final created = (body['created'] as List<dynamic>?) ?? [];
  return created.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
