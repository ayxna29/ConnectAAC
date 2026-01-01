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
  // debug status removed from UI

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
    if (card == null || card.id.isEmpty) return; // only for generated cards
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
    _loadAssets()
        .then((_) => _initFavorites())
        .then((_) => _refreshMicStatus());
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
        // On web, permission_handler may not be available; try to initialize speech directly
        try {
          final available = await _speech.initialize();
          print(
            'Speech initialized on resume (web): available=$available, hasPermission=${_speech.hasPermission}',
          );
          if (mounted)
            setState(() {
              // debug status intentionally not shown in UI
            });
        } catch (e) {
          print('Speech init error on resume (web): $e');
        }
        return;
      }

      final status = await Permission.microphone.status;
      // no-op
      // ignore: avoid_print
      print('Permission on resume: $status');
      if (status.isGranted) {
        try {
          final available = await _speech.initialize();
          // ignore: avoid_print
          print(
            'Speech initialized on resume: available=$available, hasPermission=${_speech.hasPermission}',
          );
          // update UI status (show concise status)
          if (mounted)
            setState(() {
              // debug status intentionally not shown in UI
            });
        } catch (e) {
          // ignore: avoid_print
          print('Speech init error on resume: $e');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error checking permission on resume: $e');
    }
  }

  Future<void> _refreshMicStatus() async {
    try {
      if (kIsWeb) {
        // permission_handler isn't reliable on web; attempt speech plugin init
        try {
          final available = await _speech.initialize();
          final hasPermission = _speech.hasPermission == true;
          final msg =
              'Permission: web, hasPerm:${hasPermission ? 'yes' : 'no'}, initialized:${available ? 'yes' : 'no'}';
          print('Microphone status refresh (web): $msg');
          if (mounted)
            setState(() {
              // debug status intentionally not shown in UI
            });
        } catch (e) {
          print('Failed to refresh mic status (web): $e');
          if (mounted)
            setState(() {
              // keep UI clean; don't surface debug status
            });
        }
        return;
      }

      final status = await Permission.microphone.status;
      final hasPermission = _speech.hasPermission == true;
      final initialized = _speech.isAvailable;
      final msg =
          'Permission: ${status.toString().split('.').last}, hasPerm:${hasPermission ? 'yes' : 'no'}, initialized:${initialized ? 'yes' : 'no'}';
      // ignore: avoid_print
      print('Microphone status refresh: $msg');
      // Keep UI clean; do not display debug status
      if (mounted)
        setState(() {
          // no-op
        });
    } catch (e) {
      // ignore: avoid_print
      print('Failed to refresh mic status: $e');
      if (mounted)
        setState(() {
          // do not surface debug status
        });
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
      // ignore: avoid_print
      print('TTS init error: $e');
    }
  }

  Future<void> _loadAssets() async {
    try {
      // Initialize AssetService index and load available filenames
      await AssetService.instance.init();
      final files = await AssetService.listSymbolFilenames(); // fixed
      if (mounted) {
        setState(() => _availableFilenames = files);
      }
    } catch (e) {
      // ignore asset load errors silently for now
    }
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
          //  Use backend assetFilename directly, don't remap
          _favoriteCards.add(
            GeneratedFlashcard(
              id: f.id,
              question: f.question,
              answer: f.answer,
              tags: const [],
              assetFilename: f.assetFilename, //  Use backend value
            ),
          );
        }
      });
    } catch (e) {
      print('Failed to load favorites: $e');
    }
  }

  // helper to check favorites is available via _favoriteIds set

  Future<void> _toggleFavorite(GeneratedFlashcard card) async {
    final wasFav = _favoriteIds.contains(card.id);

    // Optimistic update
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
      // Revert on error
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
      _generated = []; // Only clear generated, NOT favorites
      _preMapped = {};
      // DON'T touch _favoriteCards or _favoriteIds here
    });

    try {
      final token = ++_genToken;
      final cards = await _flashcardService.generate(caregiverInput: input);
      if (token != _genToken) return;

      final mapping = <String, String>{};
      for (final c in cards) {
        if (c.assetFilename != null) {
          final af = c.assetFilename!;
          // Prefer backend filename only if it's available locally; otherwise
          // try to resolve to a full asset path via AssetService.lookup
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
                mapping[c.answer] = resolved; // full path
              } else {
                // fallback to backend-provided name (may still fail)
                mapping[c.answer] = af;
              }
            } catch (_) {
              mapping[c.answer] = af;
            }
          }
        }
      }
      // Also add favorite cards to mapping
      for (final c in _favoriteCards) {
        if (c.assetFilename != null) {
          final af = c.assetFilename!;
          if (_availableFilenames.contains(af)) {
            mapping[c.answer] = af;
          } else {
            final base = af.replaceAll(
              RegExp(r'\.svg$', caseSensitive: false),
              '',
            );
            try {
              final resolved = await AssetService.instance.lookup(base);
              if (resolved != null) mapping[c.answer] = resolved;
            } catch (_) {}
          }
        }
      }

      setState(() {
        _generated = cards;
        _preMapped = mapping;
        _loadingGeneration = false;

        // Update favorite IDs to match regenerated cards with same answers
        final newFavoriteIds = <String>{};
        for (final favCard in _favoriteCards) {
          // Find matching card in new generation by answer
          final match = cards.firstWhere(
            (c) => c.answer.toLowerCase() == favCard.answer.toLowerCase(),
            orElse: () => favCard, // Keep old card if not found
          );
          newFavoriteIds.add(match.id);

          // Update the favorite card with new ID
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

  // Open settings and apply returned values (robust, shows error dialog on failure)
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

      if (result == null) return; // user cancelled

      // validate result entries
      final voiceRaw = result['voice'];
      final rateRaw = result['rate'];
      final volumeRaw = result['volume'];

      Map<String, String>? voice;
      if (voiceRaw is Map) {
        // convert keys/values to strings safely
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

      // apply to TTS with safe try/catch
      try {
        await _tts.setSpeechRate(_currentRate);
        await _tts.setVolume(_currentVolume);
        if (_currentVoice != null) {
          await _tts.setVoice(_currentVoice!);
        }
      } catch (e) {
        // ignore: avoid_print
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
      // navigator or other unexpected error
      // ignore: avoid_print
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

  // Placeholder: open AI optimization screen or perform action
  void _openAiOptimization() {
    // Navigate to the OptimizationPage and refresh favorites on return
    () async {
      await Navigator.of(
        context,
      ).push(CupertinoPageRoute(builder: (_) => const OptimizationPage()));
      // After returning from optimization screen, refresh favorites so Home shows updates immediately
      await _initFavorites();
    }();
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
    // Optionally trigger generation after manual entry
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    // Explicitly check/request microphone permission using permission_handler.
    try {
      if (kIsWeb) {
        // On web, ask the browser for microphone access which will trigger
        // the browser permission prompt (Chrome/Edge/Firefox will show the mic popup).
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

        // If the browser granted access, try initializing the speech plugin.
        bool available = false;
        try {
          available = await _speech.initialize(
            onStatus: (val) {
              if (mounted) setState(() => _isListening = val == 'listening');
              if (val == 'done' || val == 'notListening') {
                if (mounted) setState(() => _isListening = false);
                final text = caregiverInputController.text.trim();
                if (text.length >= 3) {
                  _generateFromInput();
                }
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
        _speech.listen(
          onResult: (val) {
            if (!mounted) return;
            caregiverInputController.text = val.recognizedWords;
            caregiverInputController.selection = TextSelection.fromPosition(
              TextPosition(offset: caregiverInputController.text.length),
            );
          },
        );
        return;
      }
      // ensure we have an up-to-date status before proceeding
      await _refreshMicStatus();

      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }

      if (status.isPermanentlyDenied) {
        // Show dialog with option to open app settings
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

      // At this point, if granted, try to initialize the speech plugin.
      // Sometimes the OS permission is granted but the plugin hasn't registered permission yet.
      if (status.isGranted) {
        bool available = false;
        try {
          available = await _speech.initialize(
            onStatus: (val) {
              if (mounted) setState(() => _isListening = val == 'listening');
              if (val == 'done' || val == 'notListening') {
                if (mounted) setState(() => _isListening = false);
                final text = caregiverInputController.text.trim();
                if (text.length >= 3) {
                  _generateFromInput();
                }
              }
            },
            onError: (val) {
              if (mounted) setState(() => _isListening = false);
              // log error, keep UI non-alarming
              print('Speech onError: $val');
            },
          );
        } catch (e) {
          print('Speech initialize error after grant: $e');
        }

        if (!available) {
          // If we couldn't initialize after permission was granted, show a helpful message
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
          // update internal state quietly (do not surface debug status)
          if (mounted)
            setState(() {
              // no-op
            });
          return;
        }

        // Good — start listening
        if (mounted) setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            if (!mounted) return;
            caregiverInputController.text = val.recognizedWords;
            caregiverInputController.selection = TextSelection.fromPosition(
              TextPosition(offset: caregiverInputController.text.length),
            );
          },
        );
        return;
      }
    } catch (e) {
      // Fallback: if permission_handler isn't available or errors occur, try original flow
      // ignore: avoid_print
      print('Permission check error: $e');
      // try initialize anyway
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (mounted) setState(() => _isListening = val == 'listening');
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
            final text = caregiverInputController.text.trim();
            if (text.length >= 3) {
              _generateFromInput();
            }
          }
        },
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
      );
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
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) {
          if (!mounted) return;
          caregiverInputController.text = val.recognizedWords;
          caregiverInputController.selection = TextSelection.fromPosition(
            TextPosition(offset: caregiverInputController.text.length),
          );
        },
      );
    }
  }

  // immediate speak for taps/keyboard (stops current and speaks right away)
  Future<void> _speakNow(String text) async {
    try {
      await _tts.stop();
      // small stabilization delay to avoid missed starts
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
      // ignore: avoid_print
      print('TTS speakNow error: $e');
    }
  }

  // speak whole output as one sentence
  Future<void> _speakAll() async {
    if (selected.isEmpty) return;
    final sentence = selected.map((s) => s.word).join(' ');
    await _speakNow(sentence);
  }

  // Get words sorted with favorites first, then generated (no duplicates)
  // called when a flashcard is tapped
  Future<void> _onFlashcardTap(String word) async {
    // ✅ Find the card to get its backend-matched assetFilename
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

    // Use the card's assetFilename (from backend) instead of re-matching
    final filename = card.assetFilename ?? _findBestFilename(word);

    setState(() {
      selected.add(SelectedCard(word, filename));
    });
    _speakNow(word);
  }

  // toggle favorite from grid
  Future<void> _onToggleFavorite(String cardId) async {
    // Find the card in _generated or _favoriteCards list
    GeneratedFlashcard? card = _generated.firstWhere(
      (c) => c.id == cardId,
      orElse: () => _favoriteCards.firstWhere(
        (c) => c.id == cardId,
        orElse: () => throw Exception('Card not found'),
      ),
    );

    // Use the proper toggleFavorite method
    await _toggleFavorite(card);
  }

  List<String> _getSortedWords() {
    // Get favorite words that aren't in current generation
    final generatedAnswers = _generated
        .map((c) => c.answer.toLowerCase())
        .toSet();
    final favWords = _favoriteCards
        .where((c) => !generatedAnswers.contains(c.answer.toLowerCase()))
        .map((c) => c.answer)
        .toList();

    // Combine: favorites first, then generated
    return [...favWords, ..._generated.map((g) => g.answer)];
  }

  // backspace: remove last
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
          final assetPath = s.assetFilename != null
              ? 'assets/mulberry-symbols/EN-symbols/${s.assetFilename}'
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
                // image on top (bigger than previous small chips, smaller than grid)
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
        // settings + AI optimization buttons (AI to the right)
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

            // mic debug UI removed per user request

            // output box with compact cards and controls
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

            // flashcard grid (favorites appear first, no separate row)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 8,
                ),
                child: FlashcardGrid(
                  onCardTap: _onFlashcardTap,
                  onToggleFavorite: _onToggleFavorite,
                  favorites: _favoriteIds, // pass card IDs instead of filenames
                  tags: _tags,
                  words: _getSortedWords(), // favorites first, then generated
                  preMapped: _preMapped,
                  availableFilenames: _availableFilenames,
                  wordToCardId: {
                    for (final card in [..._favoriteCards, ..._generated])
                      card.answer: card.id,
                  }, // map word -> card ID
                  onRate: _rateWord,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
