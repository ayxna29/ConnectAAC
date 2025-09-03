import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OptimizationPage extends StatefulWidget {
  const OptimizationPage({super.key});

  @override
  State<OptimizationPage> createState() => _OptimizationPageState();
}

class _OptimizationPageState extends State<OptimizationPage> {
  final supabase = Supabase.instance.client;
  String? _userId;
  bool _loading = true;

  static const List<String> _allFilenames = [
    'aeroplane.svg',
    'car.svg',
    'bicycle.svg',
    'dog.svg',
  ];

  Set<String> favorites = {};
  Map<String, List<String>> flashcardTags = {};
  List<String> globalTags = ['food', 'places', 'feelings', 'animals'];
  String filterTag = '';
  // per-tag example words (e.g. #food -> ['sandwich'])
  final Map<String, List<String>> tagExamples = {};
  // favorite words (UI only, stored in-memory)
  final List<String> favoriteWords = [];

  final TextEditingController _newTagController = TextEditingController();
  final TextEditingController _favWordController = TextEditingController();
  final Map<String, TextEditingController> _perTagAddControllers = {};
  final Set<String> _assetKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _loadAssetManifest();
    _initData();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    _favWordController.dispose();
    for (final c in _perTagAddControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAssetManifest() async {
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> map =
          json.decode(manifest) as Map<String, dynamic>;
      _assetKeys.addAll(map.keys);
      if (mounted) setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Could not load AssetManifest.json: $e');
    }
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _userId = null;
          _loading = false;
        });
        return;
      }
      _userId = user.id;

      // load favorites (expect rows with flashcard_id)
      try {
        final favRes = await supabase
            .from('favorites')
            .select('flashcard_id')
            .eq('user_id', _userId!);
        final rows = favRes as List<dynamic>;
        favorites = rows
            .map(
              (r) => (r as Map).containsKey('flashcard_id')
                  ? r['flashcard_id'].toString()
                  : '',
            )
            .where((s) => s.isNotEmpty)
            .toSet();
      } catch (e) {
        // ignore: avoid_print
        print('Favorites load error: $e');
      }

      // load flashcard tags
      try {
        final fcRes = await supabase.from('flashcards').select('filename,tags');
        final rows = fcRes as List<dynamic>;
        final Map<String, List<String>> loaded = {};
        for (final r in rows) {
          if (r is Map) {
            final filename = r['filename']?.toString();
            final tagsRaw = r['tags'];
            final tags = (tagsRaw is List)
                ? tagsRaw.map((t) => t.toString()).toList()
                : <String>[];
            if (filename != null && _allFilenames.contains(filename)) {
              loaded[filename] = tags;
              for (final t in tags) {
                if (!globalTags.contains(t)) globalTags.add(t);
              }
            }
          }
        }
        flashcardTags = loaded;
      } catch (e) {
        // ignore: avoid_print
        print('Flashcards load error: $e');
      }

      // load tag examples if you have a table, otherwise keep in-memory (left as-is)
    } catch (e) {
      // ignore: avoid_print
      print('Supabase init error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Persist favorite: insert row (flashcard_id, user_id) to mark favorite.
  // Remove favorite: delete row for flashcard_id + user_id.
  Future<void> _toggleFavorite(String flashcardId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSignInRequired();
      return;
    }

    final wasFav = favorites.contains(flashcardId);

    // optimistic UI
    setState(() {
      if (wasFav)
        favorites.remove(flashcardId);
      else
        favorites.add(flashcardId);
    });
    try {
      if (wasFav) {
        await supabase
            .from('favorites')
            .delete()
            .eq('flashcard_id', flashcardId)
            .eq('user_id', user.id);
      } else {
        await supabase.from('favorites').insert({
          'flashcard_id': flashcardId,
          'user_id': user.id,
        });
      }
    } catch (e) {
      // revert
      setState(() {
        if (wasFav)
          favorites.add(flashcardId);
        else
          favorites.remove(flashcardId);
      });
      _showError('Failed to toggle favorite: $e');
    }
  }

  Future<void> _setTagsForFile(String filename, List<String> tags) async {
    flashcardTags[filename] = tags;
    try {
      await supabase.from('flashcards').upsert({
        'filename': filename,
        'tags': tags,
      });
      for (final t in tags) {
        if (!globalTags.contains(t)) globalTags.add(t);
      }
      if (mounted) setState(() {});
    } catch (e) {
      // ignore: avoid_print
      print('Set tags error: $e');
    }
  }

  void _showSignInRequired() {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Sign in required'),
        content: const Text('Please sign in to save favorites and tags.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _safeSvg(String path) {
    try {
      if (_assetKeys.isNotEmpty && !_assetKeys.contains(path)) {
        return const Icon(
          CupertinoIcons.photo,
          size: 48,
          color: CupertinoColors.systemGrey,
        );
      }
      return SvgPicture.asset(
        path,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const CupertinoActivityIndicator(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('SVG load error for $path: $e');
      return const Icon(
        CupertinoIcons.photo,
        size: 48,
        color: CupertinoColors.systemGrey,
      );
    }
  }

  // UI helpers for tags & favorite words
  void _addFavoriteWord() {
    final v = _favWordController.text.trim();
    if (v.isEmpty) return;
    if (!favoriteWords.contains(v)) {
      setState(() {
        favoriteWords.add(v);
        _favWordController.clear();
      });
    }
  }

  void _removeFavoriteWord(String w) {
    setState(() => favoriteWords.remove(w));
  }

  void _createTag() {
    final t = _newTagController.text.trim();
    if (t.isEmpty) return;
    if (!globalTags.contains(t)) {
      setState(() {
        globalTags.add(t);
        tagExamples[t] = tagExamples[t] ?? [];
        _newTagController.clear();
      });
    }
  }

  void _deleteTag(String t) {
    setState(() {
      globalTags.remove(t);
      tagExamples.remove(t);
      for (final f in _allFilenames) {
        flashcardTags[f]?.remove(t);
      }
    });
  }

  void _addExampleToTag(String tag) {
    final controller = _perTagAddControllers.putIfAbsent(
      tag,
      () => TextEditingController(),
    );
    final v = controller.text.trim();
    if (v.isEmpty) return;
    final list = tagExamples[tag] ?? <String>[];
    if (!list.contains(v)) {
      list.add(v);
      tagExamples[tag] = list;
      controller.clear();
      setState(() {});
    }
  }

  Widget _tagCard(String tag) {
    final controller = _perTagAddControllers.putIfAbsent(
      tag,
      () => TextEditingController(),
    );
    final examples = tagExamples[tag] ?? [];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                child: const Icon(CupertinoIcons.delete, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoTextField(
                    controller: controller,
                    placeholder: 'Add word to #$tag',
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: const Text('+'),
                  onPressed: () => _addExampleToTag(tag),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: examples.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey5,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          examples.remove(e);
                          tagExamples[tag] = List<String>.from(examples);
                        });
                      },
                      child: const Icon(CupertinoIcons.xmark_circle, size: 18),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CupertinoActivityIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Favorite Words section
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
                        controller: _favWordController,
                        placeholder: 'Enter a word',
                        onSubmitted: (_) => _addFavoriteWord(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton.filled(
                      child: const Text('Add'),
                      onPressed: _addFavoriteWord,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: favoriteWords.map((w) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(w),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _removeFavoriteWord(w),
                            child: const Icon(CupertinoIcons.xmark, size: 18),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                // Tag System
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
                      child: const Text('Create'),
                      onPressed: _createTag,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // tag list (cards)
                Column(children: globalTags.map((t) => _tagCard(t)).toList()),

                const SizedBox(height: 20),
                // Done button
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CupertinoButton.filled(
                      child: const Text('Done'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          );

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('AI Customization'),
      ),
      child: SafeArea(child: body),
    );
  }
}
