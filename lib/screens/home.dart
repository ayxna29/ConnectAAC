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
import 'settings.dart'; // added
import 'optimization.dart';

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

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final TextEditingController caregiverInputController =
      TextEditingController();
  final List<SelectedCard> selected = [];
  late stt.SpeechToText _speech;
  bool _isListening = false;
  late FlutterTts _tts;

  // TTS settings state
  Map<String, String>? _currentVoice;
  double _currentRate = 0.5;
  double _currentVolume = 1.0;

  // local tags (keeps UI responsive)
  final Map<String, List<String>> _tags = {};

  // AI generation state
  final FlashcardService _flashcardService = FlashcardService();
  bool _loadingGeneration = false;
  List<GeneratedFlashcard> _generated = [];
  Map<String, String> _preMapped = {}; // word -> filename
  List<String> _availableFilenames = [];

  // favorites state
  final Set<String> _favoriteIds = {};
  List<GeneratedFlashcard> _favoriteCards = [];

  int _genToken = 0;

  GeneratedFlashcard? _findGeneratedByWord(String word) {
    try {
      return _generated.firstWhere(
        (g) => g.answer.toLowerCase() == word.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
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
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(1),
            child: const Text('1'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(2),
            child: const Text('2'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(3),
            child: const Text('3'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(4),
            child: const Text('4'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(5),
            child: const Text('5'),
          ),
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
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
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
    _configureTts();
    _loadAssets().then((_) => _initFavorites());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkPermissionOnResume();
    }
  }

  Future<void> _checkPermissionOnResume() async {
    try {
      if (kIsWeb) {
        try {
          final available = await _speech.initialize();
          print(
            'Speech initialized on resume (web): available=$available, hasPermission=${_speech.hasPermission}',
          );
          if (mounted) setState(() {});
        } catch (e) {
          print('Speech init error on resume (web): $e');
        }
        return;
      }

      final status = await Permission.microphone.status;
      print('Permission on resume: $status');
      if (status.isGranted) {
        try {
          final available = await _speech.initialize();
          print(
            'Speech initialized on resume: available=$available, hasPermission=${_speech.hasPermission}',
          );
          if (mounted) setState(() {});
        } catch (e) {
          print('Speech init error on resume: $e');
        }
      }
    } catch (e) {
      print('Error checking permission on resume: $e');
    }
  }

  Future<void> _refreshMicStatus() async {
    try {
      if (kIsWeb) {
        try {
          final available = await _speech.initialize();
          final hasPermission = _speech.hasPermission == true;
          print(
            'Microphone status refresh (web): hasPerm:${hasPermission ? 'yes' : 'no'}, initialized:${available ? 'yes' : 'no'}',
          );
          if (mounted) setState(() {});
        } catch (e) {
          print('Failed to refresh mic status (web): $e');
          if (mounted) setState(() {});
        }
        return;
      }

      final status = await Permission.microphone.status;
      final hasPermission = _speech.hasPermission == true;
      final initialized = _speech.isAvailable;
      print(
        'Microphone status refresh: ${status.toString().split('.').last}, hasPerm:${hasPermission ? 'yes' : 'no'}, initialized:${initialized ? 'yes' : 'no'}',
      );
      if (mounted) setState(() {});
    } catch (e) {
      print('Failed to refresh mic status: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(_currentVolume);
      await _tts.setPitch(1.0);
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}
    } catch (e) {
      print('TTS init error: $e');
    }
  }

  Future<void> _loadAssets() async {
    try {
      await AssetService.instance.init();
      final files = await AssetService.listSymbolFilenames();
      if (mounted) {
        setState(() => _availableFilenames = files);
      }
    } catch (e) {
      // ignore asset load errors silently
    }
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
          _favoriteCards.add(
            GeneratedFlashcard(
              id: f.id,
              question: f.question,
              answer: f.answer,
              tags: const [],
              assetFilename: _normalizeAssetFilename(f.assetFilename),
            ),
          );
        }
      });
    } catch (e) {
      print('Failed to load favorites: $e');
    }
  }

  Future<void> _toggleFavorite(GeneratedFlashcard card) async {
    final wasFav = _favoriteIds.contains(card.id);

    setState(() {
      if (wasFav) {
        _favoriteIds.remove(card.id);
        _favoriteCards.removeWhere((c) => c.id == card.id);
      } else {
        _favoriteIds.add(card.id);
        _favoriteCards.add(card);
      }
    });

    try {
      if (wasFav) {
        await _flashcardService.unfavoriteCard(card.id);
      } else {
        await _flashcardService.favoriteCard(card.id);
      }
    } catch (e) {
      setState(() {
        if (wasFav) {
          _favoriteIds.add(card.id);
          _favoriteCards.add(card);
        } else {
          _favoriteIds.remove(card.id);
          _favoriteCards.removeWhere((c) => c.id == card.id);
        }
      });

      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save favorite: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _generateFromInput() async {
    final input = caregiverInputController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _loadingGeneration = true;
      _generated = [];
      _preMapped = {};
    });

    try {
      final token = ++_genToken;
      print('🚀 Generating cards with token=$token for input: "$input"');
      final cards = await _flashcardService.generate(caregiverInput: input);
      print('✅ Got ${cards.length} cards (token=$token vs current=$_genToken)');
      if (token != _genToken) {
        print('⚠️ Token mismatch, discarding results');
        return;
      }

      final mapping = <String, String>{};
      for (final c in cards) {
        if (c.assetFilename != null) {
          final af = _normalizeAssetFilename(c.assetFilename);
          if (af == null) continue;
          if (_availableFilenames.contains(af)) {
            mapping[c.answer] = af;
          } else {
            final base = af.replaceAll(
              RegExp(r'\.svg$', caseSensitive: false),
              '',
            );
            try {
              final resolved = await AssetService.instance.lookup(base);
              if (resolved != null) {
                mapping[c.answer] = resolved.split('/').last;
              } else {
                mapping[c.answer] = af;
              }
            } catch (_) {
              mapping[c.answer] = af;
            }
          }
        }
      }
      for (final c in _favoriteCards) {
        if (c.assetFilename != null) {
          final af = _normalizeAssetFilename(c.assetFilename);
          if (af == null) continue;
          if (_availableFilenames.contains(af)) {
            mapping[c.answer] = af;
          } else {
            final base = af.replaceAll(
              RegExp(r'\.svg$', caseSensitive: false),
              '',
            );
            try {
              final resolved = await AssetService.instance.lookup(base);
              if (resolved != null) {
                mapping[c.answer] = resolved.split('/').last;
              }
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
            if (index != -1) {
              _favoriteCards[index] = match;
            }
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
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
          ),
        ),
      );

      if (result == null) return;

      final voiceRaw = result['voice'];
      final rateRaw = result['rate'];
      final volumeRaw = result['volume'];

      Map<String, String>? voice;
      if (voiceRaw is Map) {
        voice = voiceRaw.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }

      final rate = (rateRaw is double) ? rateRaw : _currentRate;
      final volume = (volumeRaw is double) ? volumeRaw : _currentVolume;

      setState(() {
        _currentVoice = voice;
        _currentRate = rate;
        _currentVolume = volume;
      });

      try {
        await _tts.setSpeechRate(_currentRate);
        await _tts.setVolume(_currentVolume);
        if (_currentVoice != null) {
          await _tts.setVoice(_currentVoice!);
        }
      } catch (e) {
        print('Failed to apply TTS settings: $e');
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('TTS Error'),
              content: Text('Failed to apply voice settings: $e'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      print('Error opening settings: $e');
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Could not open settings: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _openAiOptimization() async {
    await Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => const OptimizationPage()));
    await _initFavorites();
  }

  String? _findBestFilename(String word) {
    final lower = word.toLowerCase();
    double best = 0.0;
    String? pick;
    for (final f in _availableFilenames) {
      final name = f.toLowerCase().replaceAll(RegExp(r'\.svg$'), '');
      final score = StringSimilarity.compareTwoStrings(lower, name);
      if (score > best) {
        best = score;
        pick = f;
      }
    }
    return best >= 0.5 ? pick : null;
  }

  void _onKeyboardPressed() {
    final inputText = caregiverInputController.text;
    if (inputText.trim().isEmpty) return;
    final filename = _findBestFilename(inputText.trim());
    setState(() {
      selected.add(SelectedCard(inputText.trim(), filename));
    });
    _speakNow(inputText.trim());
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    try {
      if (kIsWeb) {
        final granted = await mic_perm.requestBrowserMic();
        if (!granted) {
          if (mounted) {
            showCupertinoDialog(
              context: context,
              builder: (_) => CupertinoAlertDialog(
                title: const Text('Microphone Permission'),
                content: const Text(
                  'Please allow microphone access in your browser.',
                ),
                actions: [
                  CupertinoDialogAction(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            );
          }
          return;
        }

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
              print('Speech onError (web): $val');
            },
          );
        } catch (e) {
          print('Speech initialize error on web after grant: $e');
        }

        if (!available) {
          if (mounted) {
            showCupertinoDialog(
              context: context,
              builder: (_) => CupertinoAlertDialog(
                title: const Text('Microphone Error'),
                content: const Text(
                  'Could not initialize speech recognition in the browser.',
                ),
                actions: [
                  CupertinoDialogAction(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
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
                TextPosition(offset: caregiverInputController.text.length),
              );
            },
            cancelOnError: true,
          );
        } catch (err) {
          if (mounted) setState(() => _isListening = false);
          print('Speech listen error (web): $err');
        }
        return;
      }

      await _refreshMicStatus();

      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Microphone Permission'),
              content: const Text(
                'Microphone access is required. Please enable it in app settings.',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Open Settings'),
                  onPressed: () {
                    openAppSettings();
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
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
              onError: (val) {
                if (mounted) setState(() => _isListening = false);
                print('Speech onError: $val');
              },
            );
          } catch (e) {
            print('Speech initialize error after grant: $e');
          }
        }

        if (!available) {
          if (mounted) {
            showCupertinoDialog(
              context: context,
              builder: (_) => CupertinoAlertDialog(
                title: const Text('Microphone Error'),
                content: const Text(
                  'Could not initialize speech recognition. Try restarting the app or checking OS settings.',
                ),
                actions: [
                  CupertinoDialogAction(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            );
          }
          if (mounted) setState(() => _isListening = false);
          return;
        }

        if (mounted) setState(() => _isListening = true);
        try {
          _speech.listen(
            onResult: (val) {
              if (!mounted) return;
              caregiverInputController.text = val.recognizedWords;
              caregiverInputController.selection = TextSelection.fromPosition(
                TextPosition(offset: caregiverInputController.text.length),
              );
            },
            cancelOnError: true,
          );
        } catch (err) {
          if (mounted) setState(() => _isListening = false);
          print('Speech listen error: $err');
        }
        return;
      }
    } catch (e) {
      print('Permission check error: $e');

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
            onError: (val) {
              if (mounted) setState(() => _isListening = false);
              print('Speech fallback onError: $val');
            },
          );
        } catch (initErr) {
          print('Fallback initialization error: $initErr');
        }
      }

      if (!available || _speech.hasPermission != true) {
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Microphone Permission'),
              content: const Text('Microphone access is required.'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
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
              TextPosition(offset: caregiverInputController.text.length),
            );
          },
          cancelOnError: true,
        );
      } catch (err) {
        if (mounted) setState(() => _isListening = false);
        print('Speech listen error (fallback): $err');
      }
    }
  }

  Future<void> _speakNow(String text) async {
    try {
      await _tts.stop();
      await Future.delayed(const Duration(milliseconds: 10));
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(_currentVolume);
      if (_currentVoice != null) {
        try {
          await _tts.setVoice(_currentVoice!);
        } catch (_) {}
      }
      await _tts.speak(text);
    } catch (e) {
      print('TTS speakNow error: $e');
    }
  }

  Future<void> _speakAll() async {
    if (selected.isEmpty) return;
    final sentence = selected.map((s) => s.word).join(' ');
    await _speakNow(sentence);
  }

  Future<void> _onFlashcardTap(String word) async {
    final card = [..._favoriteCards, ..._generated].firstWhere(
      (c) => c.answer == word,
      orElse: () => GeneratedFlashcard(
        id: '',
        question: '',
        answer: word,
        tags: [],
        assetFilename: null,
      ),
    );

    final filename = card.assetFilename ?? _findBestFilename(word);

    setState(() {
      selected.add(SelectedCard(word, filename));
    });
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
    final generatedAnswers = _generated
        .map((c) => c.answer.toLowerCase())
        .toSet();
    final favWords = _favoriteCards
        .where((c) => !generatedAnswers.contains(c.answer.toLowerCase()))
        .map((c) => c.answer)
        .toList();
    return [...favWords, ..._generated.map((g) => g.answer)];
  }

  void _onBackspace() {
    if (selected.isEmpty) return;
    setState(() => selected.removeLast());
  }

  void _onClear() => setState(() => selected.clear());

  Widget _buildOutputItems() {
    if (selected.isEmpty) {
      return Text(
        'Output will appear here...',
        style: TextStyle(fontSize: 16, color: CupertinoColors.inactiveGray),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: selected.map((s) {
          final filename = _normalizeAssetFilename(s.assetFilename);
          final assetPath = filename != null
              ? 'assets/mulberry-symbols/EN-symbols/$filename'
              : null;
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 72,
                  child: assetPath != null
                      ? SvgPicture.asset(assetPath, fit: BoxFit.contain)
                      : const Icon(
                          Icons.help_outline,
                          size: 48,
                          color: Colors.black26,
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.word,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build the wordToFitz map from all cards (generated + favorites).
  /// Falls back gracefully if GeneratedFlashcard doesn't have a fitz field.
  Map<String, String> _buildWordToFitz() {
    final allCards = [..._favoriteCards, ..._generated];
    final map = <String, String>{};
    for (final card in allCards) {
      if (card.fitz != null && card.fitz!.isNotEmpty) {
        map[card.answer] = card.fitz!;
      }
    }
    print('🎨 wordToFitz: $map'); // ADD THIS
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Text(
            'ConnectAAC',
            style: TextStyle(
              fontSize: 40.0,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.black,
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(255, 153, 160, 113),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  CupertinoIcons.settings,
                  size: 24,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _openAiOptimization,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(255, 153, 160, 113),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 24,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // input row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: caregiverInputController,
                      placeholder: 'Type or say a question/statement...',
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
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
                        : const Icon(
                            CupertinoIcons.sparkles,
                            size: 28,
                            color: CupertinoColors.activeGreen,
                          ),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _onKeyboardPressed,
                    child: const Icon(
                      CupertinoIcons.keyboard,
                      size: 28,
                      color: CupertinoColors.activeBlue,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _toggleListening,
                    child: Icon(
                      _isListening
                          ? CupertinoIcons.mic_fill
                          : CupertinoIcons.mic,
                      size: 28,
                      color: _isListening
                          ? CupertinoColors.systemRed
                          : CupertinoColors.activeBlue,
                    ),
                  ),
                ],
              ),
            ),

            // output box
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildOutputItems()),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.all(0),
                      onPressed: _onBackspace,
                      child: const Icon(
                        CupertinoIcons.delete_left,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.all(0),
                      onPressed: _onClear,
                      child: const Icon(
                        CupertinoIcons.clear_thick_circled,
                        size: 26,
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.all(0),
                      onPressed: _speakAll,
                      child: const Icon(
                        CupertinoIcons.speaker_2,
                        size: 26,
                        color: CupertinoColors.activeBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // flashcard grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 8,
                ),
                child: FlashcardGrid(
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
                  // ✅ Fitzgerald Key coloring — passes backend fitz values,
                  // falls back to built-in word classifier for any missing entries
                  wordToFitz: _buildWordToFitz(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
