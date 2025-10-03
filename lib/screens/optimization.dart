import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ai_service.dart';

class OptimizationPage extends StatefulWidget {
  const OptimizationPage({super.key});

  @override
  State<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends State<OptimizationPage> {
  final supabase = Supabase.instance.client;

  bool _loading = false;

  // generation input controller and selected tag for AI
  final TextEditingController _generationController = TextEditingController();
  String? _selectedTag;

  // favorites UI
  final TextEditingController _favController = TextEditingController();
  final List<String> _favoriteWords =
      []; // UI-only list of chips (keeps in sync with DB when you wire it)

  // tags
  final TextEditingController _newTagController = TextEditingController();
  final List<String> _tags =
      []; // loaded from DB (fallback defaults added in _init)
  final Map<String, TextEditingController> _perTagControllers = {};

  // flashcards (text -> image url)
  final Map<String, String> _imageForText = {};
  // new: words grouped by tag for quick UI rendering
  final Map<String, List<String>> _wordsByTag = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _favController.dispose();
    _newTagController.dispose();
    _generationController.dispose();
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
      final res = await supabase
          .from('tags')
          .select('name')
          .order('created_at', ascending: true);
      final rows = res as List<dynamic>? ?? [];
      _tags
        ..clear()
        ..addAll(
          rows
              .whereType<Map>()
              .map((r) => r['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty),
        );
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
      // leave defaults
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
      _wordsByTag.clear();
      for (final r in rows.whereType<Map>()) {
        final t = (r['text'] ?? '').toString();
        final img = (r['image_url'] ?? '').toString();
        final tag = (r['tag'] ?? '').toString();
        if (t.isNotEmpty && img.isNotEmpty) _imageForText[t] = img;
        if (t.isNotEmpty) {
          final list = _wordsByTag.putIfAbsent(
            tag.isEmpty ? '__untagged' : tag,
            () => <String>[],
          );
          if (!list.contains(t)) list.add(t);
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
      final res = await supabase.from('favorites').select('flashcard_id');
      final rows = res as List<dynamic>? ?? [];
      final ids = rows
          .whereType<Map>()
          .map((r) => r['flashcard_id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (ids.isNotEmpty) {
        final quoted = ids
            .map((s) => "'${s.replaceAll("'", "\\'")}'")
            .join(',');
        final fcRes = await supabase
            .from('flashcards')
            .select('text')
            .filter('id', 'in', '($quoted)');
        final fr = fcRes as List<dynamic>? ?? [];
        _favoriteWords
          ..clear()
          ..addAll(
            fr
                .whereType<Map>()
                .map((r) => r['text']?.toString() ?? '')
                .where((s) => s.isNotEmpty),
          );
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
    // local UI update
    if (!_favoriteWords.contains(word)) _favoriteWords.add(word);
    _favController.clear();
    setState(() {});

    // optional: if you want to persist a favorite mapping create/find flashcard and insert into favorites table
    // left out here — wire to your server / favorite logic if desired
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
      await supabase.from('tags').insert({
        'name': name,
        'user_id': supabase.auth.currentUser?.id,
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

  Future<void> _addWordToTag(String tag) async {
    final controller = _perTagControllers.putIfAbsent(
      tag,
      () => TextEditingController(),
    );
    final name = controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showDialog('Sign in required', 'You must sign in to add flashcards.');
        return;
      }
      // insert new flashcard
      final insert = await supabase.from('flashcards').insert({
        'text': name,
        'tag': tag,
        'user_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select();
      // update local grouped map for immediate UI feedback
      final list = _wordsByTag.putIfAbsent(tag, () => <String>[]);
      if (!list.contains(name)) list.add(name);
      // try to find an existing image that matches term
      final image = await _findMatchingImage(name);
      if (image != null && image.isNotEmpty) {
        // attempt to save image_url back to the inserted row if DB perms allow
        try {
          // get inserted id if available
          String? id;
          if (insert.isNotEmpty) {
            id = insert[0]['id']?.toString();
          }
          if (id != null && id.isNotEmpty) {
            await supabase
                .from('flashcards')
                .update({'image_url': image})
                .eq('id', id);
          }
        } catch (_) {
          // ignore permission issues
        }
        _imageForText[name] = image;
      }
      controller.clear();
      _showDialog('Added', '"$name" added to #$tag');
    } catch (e) {
      _showDialog('Error', 'Failed to add word: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _findMatchingImage(String term) async {
    try {
      final pattern = '%${term.replaceAll('%', '\\%')}%';
      // 1) search image_url contains term
      final r1 = await supabase
          .from('flashcards')
          .select('image_url')
          .ilike('image_url', pattern)
          .limit(1);
      final rows1 = r1 as List<dynamic>? ?? [];
      if (rows1.isNotEmpty && rows1[0] is Map) {
        final img = (rows1[0]['image_url'] ?? '').toString();
        if (img.isNotEmpty) return img;
      }
      // 2) search for common filename guesses
      final guesses = [
        '${term.toLowerCase()}.svg',
        '${term.toLowerCase()}.png',
        '${term.toLowerCase()}.jpg',
      ];
      for (final g in guesses) {
        final rg = await supabase
            .from('flashcards')
            .select('image_url')
            .ilike('image_url', '%$g%')
            .limit(1);
        final rgr = rg as List<dynamic>? ?? [];
        if (rgr.isNotEmpty && rgr[0] is Map) {
          final img = (rgr[0]['image_url'] ?? '').toString();
          if (img.isNotEmpty) return img;
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
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
      await supabase.from('tags').delete().eq('name', tag);
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
          children: _favoriteWords.map((w) {
            return Chip(
              label: Text(w),
              backgroundColor: CupertinoColors.systemGrey5,
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
            final controller = _perTagControllers.putIfAbsent(
              tag,
              () => TextEditingController(),
            );
            final words = (_wordsByTag[tag] ?? []).toList();
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: controller,
                          placeholder: 'Add word to #$tag',
                          onSubmitted: (_) => _addWordToTag(tag),
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
                          onPressed: () => _addWordToTag(tag),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // display added words under the box
                  if (words.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: words.map((w) => _wordChip(w)).toList(),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: CupertinoButton.filled(
            child: const Text('Done'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  // add this helper inside _OptimizationPageState
  Widget _wordChip(String w) {
    final img = _imageForText[w];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (img != null && img.isNotEmpty)
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: NetworkImage(img),
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white24,
              ),
              child: const Icon(Icons.text_fields, size: 16),
            ),
          const SizedBox(width: 8),
          Text(w),
        ],
      ),
    );
  }

  Future<void> _onGeneratePressed() async {
    final prompt = _generationController.text
        .trim(); // ensure you have a TextEditingController
    if (prompt.isEmpty) return;
    setState(() => _loading = true);
    try {
      final created = await generateFlashcardsFromAI(prompt, tag: _selectedTag);
      // Option A: reload from Supabase (recommended) to show saved cards:
      await _loadFlashcards();
      // Option B: merge created into local UI state if you manage it locally:
      // _localFlashcards.insertAll(0, created);
      _showDialog('Success', 'Created ${created.length} flashcards');
    } catch (e) {
      _showDialog('Error', e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
