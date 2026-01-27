import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Model for context sentence
class ContextSentence {
  final String id;
  final String text;
  ContextSentence({required this.id, required this.text});
}

class OptimizationPage extends StatefulWidget {
  const OptimizationPage({super.key});

  @override
  State<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends State<OptimizationPage> {
  final supabase = Supabase.instance.client;

  // Backend URL used for optimization endpoints. Keep in sync with FlashcardService default.
  final String backendBaseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://connectaac.onrender.com',
  );

  bool _loading = false;

  // favorites UI
  final TextEditingController _favController = TextEditingController();
  // UI list of favorites as maps with keys: id, word, asset
  final List<Map<String, String>> _favoriteItems = [];

  // tags
  final TextEditingController _newTagController = TextEditingController();
  final List<String> _tags = [];
  final Map<String, TextEditingController> _perTagControllers = {};

  // Context sentences grouped by tag
  final Map<String, List<ContextSentence>> _tagContexts = {};

  // flashcards (text -> image url)
  final Map<String, String> _imageForText = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _favController.dispose();
    _newTagController.dispose();
    for (final c in _perTagControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    try {
      await _loadTags();
      await _loadFlashcards();
      await _loadFavorites();
    } catch (e) {
      // ignore for UI demo
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTags() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final res = await supabase
          .from('user_tags')
          .select('id, tag_name, tag_contexts (id, context_text)')
          .eq('user_id', user.id)
          .order('created_at', ascending: true);
      final rows = res as List<dynamic>? ?? [];
      _tags.clear();
      _tagContexts.clear();
      for (final r in rows.whereType<Map>()) {
        final tagName = r['tag_name']?.toString() ?? '';
        if (tagName.isNotEmpty) {
          _tags.add(tagName);
          final contexts = <ContextSentence>[];
          final ctxRows = r['tag_contexts'] as List<dynamic>? ?? [];
          for (final ctx in ctxRows.whereType<Map>()) {
            final ctxId = ctx['id']?.toString() ?? '';
            final ctxText = ctx['context_text']?.toString() ?? '';
            if (ctxText.isNotEmpty && ctxId.isNotEmpty) {
              contexts.add(ContextSentence(id: ctxId, text: ctxText));
            }
          }
          _tagContexts[tagName] = contexts;
        }
      }
      if (_tags.isEmpty) {
        _tags.addAll([
          'food',
          'transportation',
          'animals',
          'places',
          'feelings',
        ]);
      }
      setState(() {});
    } catch (e) {
      // fallback defaults
      if (_tags.isEmpty) {
        _tags.addAll([
          'food',
          'transportation',
          'animals',
          'places',
          'feelings',
        ]);
      }
    }
  }

  Future<void> _loadFlashcards() async {
    try {
      final res = await supabase
          .from('flashcards')
          .select('text,image_url,tag');
      final rows = res as List<dynamic>? ?? [];
      _imageForText.clear();
      for (final r in rows.whereType<Map>()) {
        final t = (r['text'] ?? '').toString();
        final img = (r['image_url'] ?? '').toString();
        if (t.isNotEmpty && img.isNotEmpty) _imageForText[t] = img;
        if (t.isNotEmpty) {
          // ...existing code...
        }
      }
      setState(() {});
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      // Fetch merged favorites from backend so Optimization UI shows all favorites
      final session = supabase.auth.currentSession;
      final jwt = session?.accessToken;
      if (jwt == null) return;
      final resp = await http.get(
        Uri.parse('$backendBaseUrl/optimization/favorites'),
        headers: {
          'Authorization': 'Bearer ${jwt}',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode == 200) {
        final body = resp.body;
        try {
          final parsed = body.isNotEmpty
              ? Map<String, dynamic>.from(json.decode(body))
              : {};
          final list = (parsed['favorites'] as List<dynamic>?) ?? <dynamic>[];
          _favoriteItems.clear();
          for (final m in list.whereType<Map>()) {
            final word = (m['word'] ?? m['answer'] ?? '').toString();
            final id = (m['id'] ?? m['card_id'] ?? m['id'] ?? '').toString();
            final asset = (m['asset_filename'] ?? '').toString();
            if (word.isNotEmpty) {
              _favoriteItems.add({'id': id, 'word': word, 'asset': asset});
              if (asset.isNotEmpty) _imageForText[word] = asset;
            }
          }
        } catch (e) {
          // ignore parse errors
        }
      }
      setState(() {});
    } catch (e) {
      // ignore
    }
  }

  // UI actions (these call DB where appropriate)
  Future<void> _addFavoriteWord() async {
    final word = _favController.text.trim();
    if (word.isEmpty) return;
    // local UI update immediately for responsiveness
    if (!_favoriteItems.any((it) => it['word'] == word)) {
      _favoriteItems.add({'id': '', 'word': word, 'asset': ''});
    }
    _favController.clear();
    setState(() {});

    // Persist via server so a flashcard + main favorite are created and it appears on the Home screen.
    final session = supabase.auth.currentSession;
    final jwt = session?.accessToken;
    if (jwt == null) return; // not signed in, UI still shows local chip

    try {
      final resp = await http.post(
        Uri.parse('$backendBaseUrl/optimization/favorites'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${jwt}',
        },
        body: '{"word": "${word.replaceAll('"', '\\"')}"}',
      );
      if (resp.statusCode == 200) {
        // success: backend created user_favorites and flashcard favorite.
        // Parse returned merged favorites and update local UI immediately
        try {
          final parsed = resp.body.isNotEmpty
              ? json.decode(resp.body) as Map<String, dynamic>
              : {};
          final list = (parsed['favorites'] as List<dynamic>?) ?? <dynamic>[];
          _favoriteItems.clear();
          for (final m in list.whereType<Map>()) {
            final word = (m['word'] ?? m['answer'] ?? '').toString();
            final id = (m['id'] ?? m['card_id'] ?? '').toString();
            final asset = (m['asset_filename'] ?? '').toString();
            if (word.isNotEmpty) {
              _favoriteItems.add({'id': id, 'word': word, 'asset': asset});
              if (asset.isNotEmpty) _imageForText[word] = asset;
            }
          }
        } catch (e) {
          // ignore parse issues but keep UI responsive
        }
      } else if (resp.statusCode == 409) {
        // already exists - ignore
      } else {
        // keep UI responsive but log error
        print(
          'Failed to create optimization favorite: ${resp.statusCode} ${resp.body}',
        );
      }
    } catch (e) {
      print('Error calling optimization favorite endpoint: $e');
    }
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    if (_tags.contains(name)) {
      _newTagController.clear();
      return;
    }
    setState(() => _loading = true);
    try {
      // Persist tag as a user-specific tag so it appears in _loadTags
      await supabase.from('user_tags').insert({
        'tag_name': name,
        'user_id': supabase.auth.currentUser?.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _tags.add(name);
      _newTagController.clear();
      setState(() {});
    } catch (e) {
      // show error
      _showDialog('Error', 'Could not create tag: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteTag(String tag) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete tag'),
        content: Text('Delete category "#$tag"? Flashcards will remain.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            child: const Text(
              'Delete',
              style: TextStyle(color: CupertinoColors.systemRed),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showDialog('Sign in required', 'You must sign in to delete tags.');
        return;
      }
      await supabase
          .from('user_tags')
          .delete()
          .eq('user_id', user.id)
          .eq('tag_name', tag);
      _tags.remove(tag);
      setState(() {});
    } catch (e) {
      _showDialog('Error', 'Could not delete tag: $e');
    }
  }

  void _showDialog(String title, String body) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _favoriteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Favorite Words',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add words to always have available in the favorites section.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _favController,
                placeholder: 'Enter a word',
                onSubmitted: (_) => _addFavoriteWord(),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton.filled(
              onPressed: _addFavoriteWord,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _favoriteItems.map((item) {
            final word = item['word'] ?? '';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(word),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      // delete optimization favorite (if id present)
                      final id = item['id'] ?? '';
                      if (id.isEmpty) {
                        // remove local optimistic entry
                        setState(
                          () => _favoriteItems.removeWhere(
                            (it) => it['word'] == word,
                          ),
                        );
                        return;
                      }
                      final session = supabase.auth.currentSession;
                      final jwt = session?.accessToken;
                      if (jwt == null) return;
                      try {
                        final resp = await http.delete(
                          Uri.parse(
                            '$backendBaseUrl/optimization/favorites/$id',
                          ),
                          headers: {
                            'Authorization': 'Bearer ${jwt}',
                            'Content-Type': 'application/json',
                          },
                        );
                        if (resp.statusCode == 200) {
                          setState(
                            () => _favoriteItems.removeWhere(
                              (it) => it['id'] == id || it['word'] == word,
                            ),
                          );
                        } else {
                          // ignore or show error
                        }
                      } catch (e) {
                        // ignore
                      }
                    },
                    child: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _tagSystem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tag System',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Create and manage tags to organize vocabulary by categories.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _newTagController,
                placeholder: 'Create a new tag (e.g. #food)',
                onSubmitted: (_) => _createTag(),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton.filled(
              onPressed: _createTag,
              child: const Text('Create'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: _tags.map((tag) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#$tag',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _deleteTag(tag),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // context sentence section
                  _contextSentenceSection(tag),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // 'Done' button removed per UX request; user can navigate back using app controls.
      ],
    );
  }

  Future<void> _addContextSentence(String tag) async {
    final controller = _perTagControllers.putIfAbsent(
      tag,
      () => TextEditingController(),
    );
    final text = controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showDialog('Sign in required', 'You must sign in to add context.');
        return;
      }
      // Ensure tag exists in user_tags, create if missing
      var tagRes = await supabase
          .from('user_tags')
          .select('id')
          .eq('user_id', user.id)
          .eq('tag_name', tag)
          .maybeSingle();
      if (tagRes == null || tagRes['id'] == null) {
        // Insert user_tag if not found
        final inserted = await supabase
            .from('user_tags')
            .insert({
              'user_id': user.id,
              'tag_name': tag,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select()
            .maybeSingle();
        if (inserted == null || inserted['id'] == null) {
          _showDialog('Error', 'Could not create tag for context.');
          return;
        }
        tagRes = inserted;
      }
      final tagId = tagRes['id'].toString();
      // Insert context sentence into tag_contexts
      final insert = await supabase.from('tag_contexts').insert({
        'tag_id': tagId,
        'context_text': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select();
      if (insert.isNotEmpty) {
        final ctxId = insert[0]['id']?.toString() ?? '';
        final ctx = ContextSentence(id: ctxId, text: text);
        final list = _tagContexts.putIfAbsent(tag, () => <ContextSentence>[]);
        list.add(ctx);
      } else {
        _showDialog('Error', 'Insert returned empty result.');
      }
      controller.clear();
      setState(() {});
    } catch (e) {
      _showDialog('Error', 'Failed to add context: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _contextSentenceRow(String tag, ContextSentence ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text('- ${ctx.text}')),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blueGrey, size: 20),
            onPressed: () => _editContextSentence(tag, ctx),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _deleteContextSentence(tag, ctx),
          ),
        ],
      ),
    );
  }

  Future<void> _editContextSentence(String tag, ContextSentence ctx) async {
    final controller = TextEditingController(text: ctx.text);
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit context sentence'),
        content: TextField(
          controller: controller,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Context sentence'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    final newText = result.trim();
    if (newText.isEmpty || newText == ctx.text) return;
    setState(() => _loading = true);
    try {
      await supabase
          .from('tag_contexts')
          .update({'context_text': newText})
          .eq('id', ctx.id);
      final list = _tagContexts[tag];
      if (list != null) {
        final index = list.indexWhere((c) => c.id == ctx.id);
        if (index != -1)
          list[index] = ContextSentence(id: ctx.id, text: newText);
      }
      setState(() {});
    } catch (e) {
      _showDialog('Error', 'Failed to update context: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteContextSentence(String tag, ContextSentence ctx) async {
    setState(() => _loading = true);
    try {
      await supabase.from('tag_contexts').delete().eq('id', ctx.id);
      final list = _tagContexts[tag];
      if (list != null) {
        list.removeWhere((c) => c.id == ctx.id);
      }
      setState(() {});
    } catch (e) {
      _showDialog('Error', 'Failed to delete context: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _contextSentenceSection(String tag) {
    final controller = _perTagControllers.putIfAbsent(
      tag,
      () => TextEditingController(),
    );
    final contexts = _tagContexts[tag] ?? [];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Context Sentences',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          // existing contexts
          if (contexts.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: contexts
                  .map((ctx) => _contextSentenceRow(tag, ctx))
                  .toList(),
            )
          else
            const Text('No context sentences yet.'),
          const SizedBox(height: 8),
          // new context input
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  placeholder: 'Add context sentence',
                  onSubmitted: (_) => _addContextSentence(tag),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () => _addContextSentence(tag),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('AI Customization'),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _favoriteSection(),
                    const SizedBox(height: 20),
                    _tagSystem(),
                  ],
                ),
              ),
      ),
    );
  }
}
