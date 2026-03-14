import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/mic_permission.dart' as mic_perm;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:string_similarity/string_similarity.dart';
import '../widgets/flashcard_grid.dart';
import '../services/flashcard_service.dart';
import '../services/asset_service.dart';
import '../services/ai_service.dart' show sendFlashcardFeedback;
import 'settings.dart';
import 'optimization.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectedCard {
  final String word;
  final String? assetFilename;
  SelectedCard(this.word, this.assetFilename);
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TextEditingController caregiverInputController = TextEditingController();
  final List<SelectedCard> selected = [];
  late stt.SpeechToText _speech;
  bool _isListening = false;
  late FlutterTts _tts;
  late AnimationController _shimmerController;

  Map<String, String>? _currentVoice;
  double _currentRate = 0.5;
  double _currentVolume = 1.0;

  final Map<String, List<String>> _tags = {};

  final FlashcardService _flashcardService = FlashcardService();
  bool _loadingGeneration = false;
  List<GeneratedFlashcard> _generated = [];
  Map<String, String> _preMapped = {};
  List<String> _availableFilenames = [];

  final Set<String> _favoriteIds = {};
  List<GeneratedFlashcard> _favoriteCards = [];

  int _genToken = 0;
  int _cardCount = 12;

  static const Map<int, int> _countToCols = {
    6: 2, 9: 3, 12: 3, 16: 4, 20: 4, 25: 5, 30: 5, 36: 6, 42: 7,
  };
  int get _gridCols => _countToCols[_cardCount] ?? 4;

  GeneratedFlashcard? _findGeneratedByWord(String word) {
    try {
      return _generated.firstWhere((g) => g.answer.toLowerCase() == word.toLowerCase());
    } catch (_) { return null; }
  }

  Future<void> _loadCardCount() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('card_count') ?? 12;
    if (mounted) setState(() => _cardCount = saved);
  }

  Future<void> _rateWord(String word, String? filename) async {
    final card = _findGeneratedByWord(word);
    if (card == null || card.id.isEmpty) return;
    final rating = await showCupertinoDialog<int>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Rate "${card.answer}"'),
        content: const Text('How helpful was this flashcard?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(1), child: const Text('1')),
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(2), child: const Text('2')),
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(3), child: const Text('3')),
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(4), child: const Text('4')),
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(5), child: const Text('5')),
        ],
      ),
    );
    if (rating == null) return;
    try {
      await sendFlashcardFeedback(cardId: card.id, rating: rating);
    } catch (e) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Feedback Error'),
          content: Text(e.toString()),
          actions: [CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _shimmerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _configureTts();
    _loadAssets().then((_) => _initFavorites());
    _loadCardCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _checkPermissionOnResume();
  }

  Future<void> _checkPermissionOnResume() async {
    try {
      if (kIsWeb) {
        try {
          final available = await _speech.initialize();
          if (mounted) setState(() {});
        } catch (e) {}
        return;
      }
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        try {
          await _speech.initialize();
          if (mounted) setState(() {});
        } catch (e) {}
      }
    } catch (e) {}
  }

  Future<void> _refreshMicStatus() async {
    try {
      if (kIsWeb) {
        try {
          await _speech.initialize();
          if (mounted) setState(() {});
        } catch (e) { if (mounted) setState(() {}); }
        return;
      }
      if (mounted) setState(() {});
    } catch (e) { if (mounted) setState(() {}); }
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(_currentVolume);
      await _tts.setPitch(1.0);
      try { await _tts.awaitSpeakCompletion(true); } catch (_) {}
    } catch (e) {}
  }

  Future<void> _loadAssets() async {
    try {
      await AssetService.instance.init();
      final files = await AssetService.listSymbolFilenames();
      if (mounted) setState(() => _availableFilenames = files);
    } catch (e) {}
  }

  String? _normalizeAssetFilename(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll('\\', '/').trim();
    if (cleaned.isEmpty) return null;
    return cleaned.split('/').last;
  }

  Future<void> _initFavorites() async {
    try {
      final favs = await _flashcardService.fetchFavorites();
      if (!mounted) return;
      setState(() {
        _favoriteIds.clear();
        _favoriteCards.clear();
        for (final f in favs) {
          _favoriteIds.add(f.id);
          _favoriteCards.add(GeneratedFlashcard(
            id: f.id, question: f.question, answer: f.answer,
            tags: const [], assetFilename: _normalizeAssetFilename(f.assetFilename),
          ));
        }
      });
    } catch (e) {}
  }

  Future<void> _toggleFavorite(GeneratedFlashcard card) async {
    final wasFav = _favoriteIds.contains(card.id);
    setState(() {
      if (wasFav) { _favoriteIds.remove(card.id); _favoriteCards.removeWhere((c) => c.id == card.id); }
      else { _favoriteIds.add(card.id); _favoriteCards.add(card); }
    });
    try {
      if (wasFav) await _flashcardService.unfavoriteCard(card.id);
      else await _flashcardService.favoriteCard(card.id);
    } catch (e) {
      setState(() {
        if (wasFav) { _favoriteIds.add(card.id); _favoriteCards.add(card); }
        else { _favoriteIds.remove(card.id); _favoriteCards.removeWhere((c) => c.id == card.id); }
      });
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save favorite: $e'),
            actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(context))],
          ),
        );
      }
    }
  }

  Future<void> _generateFromInput() async {
    final input = caregiverInputController.text.trim();
    if (input.isEmpty) return;
    setState(() { _loadingGeneration = true; _generated = []; _preMapped = {}; });
    try {
      final token = ++_genToken;
      final cards = await _flashcardService.generate(caregiverInput: input);
      if (token != _genToken) return;

      final mapping = <String, String>{};
      for (final c in cards) {
        if (c.assetFilename != null) {
          final af = _normalizeAssetFilename(c.assetFilename);
          if (af == null) continue;
          if (_availableFilenames.contains(af)) { mapping[c.answer] = af; }
          else {
            final base = af.replaceAll(RegExp(r'\.svg$', caseSensitive: false), '');
            try {
              final resolved = await AssetService.instance.lookup(base);
              if (resolved != null) { mapping[c.answer] = resolved.split('/').last; } else { mapping[c.answer] = af; }
            } catch (_) { mapping[c.answer] = af; }
          }
        }
      }
      for (final c in _favoriteCards) {
        if (c.assetFilename != null) {
          final af = _normalizeAssetFilename(c.assetFilename);
          if (af == null) continue;
          if (_availableFilenames.contains(af)) { mapping[c.answer] = af; }
          else {
            final base = af.replaceAll(RegExp(r'\.svg$', caseSensitive: false), '');
            try {
              final resolved = await AssetService.instance.lookup(base);
              if (resolved != null) { mapping[c.answer] = resolved.split('/').last; }
            } catch (_) {}
          }
        }
      }

      setState(() {
        _generated = cards;
        _preMapped = mapping;
        _loadingGeneration = false;
        final newFavoriteIds = <String>{};
        for (final favCard in _favoriteCards) {
          final match = cards.firstWhere(
            (c) => c.answer.toLowerCase() == favCard.answer.toLowerCase(),
            orElse: () => favCard,
          );
          newFavoriteIds.add(match.id);
          if (match.id != favCard.id) {
            final index = _favoriteCards.indexWhere((c) => c.id == favCard.id);
            if (index != -1) _favoriteCards[index] = match;
          }
        }
        _favoriteIds.clear();
        _favoriteIds.addAll(newFavoriteIds);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingGeneration = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Generation Error'),
            content: Text('$e\nCheck backend running & CORS.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      final result = await Navigator.of(context).push<Map<String, Object?>>(
        CupertinoPageRoute(
          builder: (_) => SettingsPage(
            initialVoice: _currentVoice,
            initialRate: _currentRate,
            initialVolume: _currentVolume,
            initialCardCount: _cardCount,
          ),
        ),
      );
      if (result == null) return;
      final voiceRaw = result['voice'];
      final rateRaw = result['rate'];
      final volumeRaw = result['volume'];
      Map<String, String>? voice;
      if (voiceRaw is Map) voice = voiceRaw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      final rate = (rateRaw is double) ? rateRaw : _currentRate;
      final volume = (volumeRaw is double) ? volumeRaw : _currentVolume;
      final cardCountRaw = result['cardCount'];
      final cardCount = (cardCountRaw is int) ? cardCountRaw : _cardCount;
      setState(() { _currentVoice = voice; _currentRate = rate; _currentVolume = volume; _cardCount = cardCount; });
      try {
        await _tts.setSpeechRate(_currentRate);
        await _tts.setVolume(_currentVolume);
        if (_currentVoice != null) await _tts.setVoice(_currentVoice!);
      } catch (e) {}
    } catch (e) {}
  }

  Future<void> _openAiOptimization() async {
    await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const OptimizationPage()));
    await _initFavorites();
  }

  String? _findBestFilename(String word) {
    final lower = word.toLowerCase();
    double best = 0.0;
    String? pick;
    for (final f in _availableFilenames) {
      final name = f.toLowerCase().replaceAll(RegExp(r'\.svg$'), '');
      final score = StringSimilarity.compareTwoStrings(lower, name);
      if (score > best) { best = score; pick = f; }
    }
    return best >= 0.5 ? pick : null;
  }

  void _onKeyboardPressed() {
    final inputText = caregiverInputController.text;
    if (inputText.trim().isEmpty) return;
    final filename = _findBestFilename(inputText.trim());
    setState(() { selected.add(SelectedCard(inputText.trim(), filename)); });
    _speakNow(inputText.trim());
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    // ── Web: call speech.initialize() directly — triggers getUserMedia on mobile browsers ──
    if (kIsWeb) {
      bool available = false;
      try {
        available = await _speech.initialize(
          onStatus: (val) {
            if (mounted) setState(() => _isListening = val == 'listening');
            if (val == 'done' || val == 'notListening') {
              if (mounted) setState(() => _isListening = false);
              final text = caregiverInputController.text.trim();
              if (text.length >= 3) _generateFromInput();
            }
          },
          onError: (val) {
            if (mounted) setState(() => _isListening = false);
          },
        );
      } catch (e) {}
      if (!available) {
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Microphone Error'),
              content: const Text('Could not access microphone. Please allow microphone access in your browser settings.'),
              actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.of(context).pop())],
            ),
          );
        }
        return;
      }
      if (mounted) setState(() => _isListening = true);
      try {
        _speech.listen(
          onResult: (val) {
            if (!mounted) return;
            caregiverInputController.text = val.recognizedWords;
            caregiverInputController.selection = TextSelection.fromPosition(
              TextPosition(offset: caregiverInputController.text.length));
          },
          cancelOnError: true,
        );
      } catch (err) {
        if (mounted) setState(() => _isListening = false);
      }
      return;
    }

    // ── Native (iOS/Android) ──
    try {
      await _refreshMicStatus();
      var status = await Permission.microphone.status;
      if (!status.isGranted) status = await Permission.microphone.request();
      if (status.isPermanentlyDenied) {
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Microphone Permission'),
              content: const Text('Please enable microphone access in app settings.'),
              actions: [
                CupertinoDialogAction(child: const Text('Open Settings'), onPressed: () { openAppSettings(); Navigator.of(context).pop(); }),
                CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          );
        }
        return;
      }
      if (status.isGranted) {
        bool available = _speech.isAvailable;
        if (!available) {
          try {
            available = await _speech.initialize(
              onStatus: (val) {
                if (mounted) setState(() => _isListening = val == 'listening');
                if (val == 'done' || val == 'notListening') {
                  if (mounted) setState(() => _isListening = false);
                  final text = caregiverInputController.text.trim();
                  if (text.length >= 3) _generateFromInput();
                }
              },
              onError: (val) { if (mounted) setState(() => _isListening = false); },
            );
          } catch (e) {}
        }
        if (!available) { if (mounted) setState(() => _isListening = false); return; }
        if (mounted) setState(() => _isListening = true);
        try {
          _speech.listen(
            onResult: (val) {
              if (!mounted) return;
              caregiverInputController.text = val.recognizedWords;
              caregiverInputController.selection = TextSelection.fromPosition(
                TextPosition(offset: caregiverInputController.text.length));
            },
            cancelOnError: true,
          );
        } catch (err) { if (mounted) setState(() => _isListening = false); }
      }
    } catch (e) { if (mounted) setState(() => _isListening = false); }
  }

  Future<void> _speakNow(String text) async {
    try {
      await _tts.stop();
      await Future.delayed(const Duration(milliseconds: 10));
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(_currentVolume);
      if (_currentVoice != null) { try { await _tts.setVoice(_currentVoice!); } catch (_) {} }
      await _tts.speak(text);
    } catch (e) {}
  }

  Future<void> _speakAll() async {
    if (selected.isEmpty) return;
    final sentence = selected.map((s) => s.word).join(' ');
    await _speakNow(sentence);
  }

  Future<void> _onFlashcardTap(String word) async {
    final premappedFilename = _preMapped[word];
    String? filename;
    if (premappedFilename != null) {
      final norm = _normalizeAssetFilename(premappedFilename);
      filename = (norm != null && norm.toLowerCase() != 'blank.svg') ? norm : null;
    } else {
      final card = [..._favoriteCards, ..._generated].firstWhere(
        (c) => c.answer == word,
        orElse: () => GeneratedFlashcard(id: '', question: '', answer: word, tags: [], assetFilename: null),
      );
      final normCard = _normalizeAssetFilename(card.assetFilename);
      filename = (normCard != null && normCard.toLowerCase() != 'blank.svg')
          ? normCard
          : _findBestFilename(word);
    }
    setState(() { selected.add(SelectedCard(word, filename)); });
    _speakNow(word);
  }

  Future<void> _onToggleFavorite(String cardId) async {
    GeneratedFlashcard? card = _generated.firstWhere(
      (c) => c.id == cardId,
      orElse: () => _favoriteCards.firstWhere(
        (c) => c.id == cardId,
        orElse: () => throw Exception('Card not found'),
      ),
    );
    await _toggleFavorite(card);
  }

  List<String> _getSortedWords() {
    final generatedAnswers = _generated.map((c) => c.answer.toLowerCase()).toSet();
    final favWords = _favoriteCards
        .where((c) => !generatedAnswers.contains(c.answer.toLowerCase()))
        .map((c) => c.answer).toList();
    return [...favWords, ..._generated.map((g) => g.answer)];
  }

  void _onBackspace() {
    if (selected.isEmpty) return;
    setState(() => selected.removeLast());
  }

  void _onClear() => setState(() => selected.clear());

  Widget _buildOutputItems() {
    if (selected.isEmpty) {
      return const Text('Output will appear here...',
          style: TextStyle(fontSize: 16, color: CupertinoColors.inactiveGray));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: selected.map((s) {
          final filename = _normalizeAssetFilename(s.assetFilename);
          final isBlank = filename == null || filename.toLowerCase() == 'blank.svg';
          final assetPath = !isBlank ? 'assets/mulberry-symbols/EN-symbols/$filename' : null;
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: CupertinoColors.systemGrey5, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 72,
                  child: assetPath != null
                      ? SvgPicture.asset(assetPath, fit: BoxFit.contain)
                      : Container(
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                          child: Center(child: Text(s.word, textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54))),
                        ),
                ),
                const SizedBox(height: 6),
                Text(s.word, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // Shimmer placeholder card shown while loading
  Widget _buildShimmerCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final shimmerValue = _shimmerController.value;
        final color = Color.lerp(
          const Color(0xFFE8E8E8),
          const Color(0xFFF8F8F8),
          (shimmerValue * 2).clamp(0.0, 1.0),
        )!;
        return Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFFDDDDDD), const Color(0xFFEEEEEE), shimmerValue)!,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Container(
                height: 10,
                width: 50,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFFDDDDDD), const Color(0xFFEEEEEE), shimmerValue)!,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, String> _buildWordToFitz() {
    final allCards = [..._favoriteCards, ..._generated];
    final map = <String, String>{};
    for (final card in allCards) {
      if (card.fitz != null && card.fitz!.isNotEmpty) map[card.answer] = card.fitz!;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 28.0, fontWeight: FontWeight.bold, color: Colors.black),
              children: [
                TextSpan(text: 'Connect'),
                TextSpan(text: 'AAC', style: TextStyle(color: Color(0xFF64B5F6))),
              ],
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openSettings,
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF0F0F0)),
                padding: const EdgeInsets.all(8),
                child: const Icon(CupertinoIcons.settings, size: 24, color: Color(0xFF888888)),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openAiOptimization,
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF64B5F6)),
                padding: const EdgeInsets.all(8),
                child: const Icon(CupertinoIcons.sparkles, size: 24, color: CupertinoColors.white),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: caregiverInputController,
                      placeholder: 'Type or say a question/statement...',
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _loadingGeneration ? null : _generateFromInput,
                    child: _loadingGeneration
                        ? const CupertinoActivityIndicator()
                        : const Icon(CupertinoIcons.sparkles, size: 28, color: CupertinoColors.activeGreen),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _onKeyboardPressed,
                    child: const Icon(CupertinoIcons.keyboard, size: 28, color: CupertinoColors.activeBlue),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _toggleListening,
                    child: Icon(
                      _isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                      size: 28,
                      color: _isListening ? CupertinoColors.systemRed : CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                decoration: BoxDecoration(color: CupertinoColors.systemGrey6, borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: _buildOutputItems()),
                    const SizedBox(width: 8),
                    CupertinoButton(padding: EdgeInsets.all(0), onPressed: _onBackspace,
                        child: const Icon(CupertinoIcons.delete_left, color: CupertinoColors.systemGrey)),
                    const SizedBox(width: 8),
                    CupertinoButton(padding: EdgeInsets.all(0), onPressed: _onClear,
                        child: const Icon(CupertinoIcons.clear_thick_circled, size: 26, color: CupertinoColors.destructiveRed)),
                    const SizedBox(width: 8),
                    CupertinoButton(padding: EdgeInsets.all(0), onPressed: _speakAll,
                        child: const Icon(CupertinoIcons.speaker_2, size: 26, color: CupertinoColors.activeBlue)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
                child: _loadingGeneration
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final cols = _gridCols;
                          final rows = (_cardCount / cols).ceil();
                          return GridView.count(
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: cols,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            padding: const EdgeInsets.all(10),
                            childAspectRatio: 1.0,
                            children: List.generate(
                              (cols * rows).clamp(0, _cardCount),
                              (_) => _buildShimmerCard(),
                            ),
                          );
                        },
                      )
                    : FlashcardGrid(
                        onCardTap: _onFlashcardTap,
                        onToggleFavorite: _onToggleFavorite,
                        favorites: _favoriteIds,
                        tags: _tags,
                        words: _getSortedWords(),
                        preMapped: _preMapped,
                        availableFilenames: _availableFilenames,
                        wordToCardId: {
                          for (final card in [..._favoriteCards, ..._generated])
                            card.answer: card.id,
                        },
                        onRate: _rateWord,
                        wordToFitz: _buildWordToFitz(),
                        maxCards: _cardCount,
                        gridCols: _gridCols,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}