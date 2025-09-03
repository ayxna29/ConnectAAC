import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:string_similarity/string_similarity.dart';
import '../widgets/flashcard_grid.dart';
import 'settings.dart'; // added
import 'optimization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _MyHomePageState extends State<MyHomePage> {
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

  static const List<String> _availableFilenames = [
    "aeroplane.svg",
    "car.svg",
    "bicycle.svg",
    "dog.svg",
  ];

  // local favorites/tags (keeps UI responsive; persisted in OptimizationPage)
  final Set<String> _favorites = {};
  final Map<String, List<String>> _tags = {};

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _configureTts();
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
    // Navigate to the OptimizationPage so user can manage tags & favorites
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => const OptimizationPage()));
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
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (mounted) setState(() => _isListening = val == 'listening');
        if (val == 'done' || val == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (val) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (!available || !await _speech.hasPermission) {
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

  // called when a flashcard is tapped
  Future<void> _onFlashcardTap(String word) async {
    final filename = _findBestFilename(word);
    setState(() {
      selected.add(SelectedCard(word, filename));
    });
    // speak immediately, non-blocking UI
    _speakNow(word);
  }

  // toggle favorite from grid
  void _onToggleFavorite(String idOrFilename) {
    // grid passes filename if available else the word
    String? filename = idOrFilename;
    if (!filename.endsWith('.svg')) {
      // try to map word -> filename
      final mapped = _findBestFilename(filename);
      filename = mapped;
    }
    if (filename == null) return;
    final nonNullFilename = filename;
    // optimistic local update
    setState(() {
      if (_favorites.contains(nonNullFilename))
        _favorites.remove(nonNullFilename);
      else
        _favorites.add(nonNullFilename);
    });

    // persist to Supabase
    _persistFavorite(nonNullFilename, _favorites.contains(nonNullFilename));
  }

  Future<void> _persistFavorite(String filename, bool add) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        // show sign-in required dialog
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Sign in required'),
            content: const Text('Please sign in to save favorites.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
        return;
      }

      // Persist favorites using your schema (flashcard_id, user_id).
      // Add -> insert a row; Remove -> delete row for flashcard_id + user_id.
      final table = supabase.from('favorites');
      if (add) {
        await table.insert({'flashcard_id': filename, 'user_id': user.id});
      } else {
        await table
            .delete()
            .eq('flashcard_id', filename)
            .eq('user_id', user.id);
      }
      // no special error field expected; just rely on exception on failure
    } catch (e) {
      // revert local change on error
      setState(() {
        if (_favorites.contains(filename))
          _favorites.remove(filename);
        else
          _favorites.add(filename);
      });
      // show a simple alert
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save favorite: $e'),
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
                  favorites: _favorites,
                  tags: _tags,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
