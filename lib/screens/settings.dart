import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  final Map<String, String>? initialVoice;
  final double initialRate;
  final double initialVolume;
  final int initialCardCount;

  const SettingsPage({
    super.key,
    this.initialVoice,
    required this.initialRate,
    required this.initialVolume,
    this.initialCardCount = 12,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FlutterTts _localTts = FlutterTts();
  List<Map<String, dynamic>> _voices = [];
  Map<String, String>? _selectedVoice;
  double _rate = 0.5;
  double _volume = 1.0;
  int _cardCount = 12;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _rate = widget.initialRate;
    _volume = widget.initialVolume;
    _selectedVoice = widget.initialVoice;
    _cardCount = widget.initialCardCount;
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final raw = await _localTts.getVoices;
      if (raw != null && raw is List) {
        _voices = raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
    } catch (_) {
      _voices = [];
    }
    setState(() => _loading = false);
  }

  String _voiceLabel(Map<String, dynamic> v) {
    final name = (v['name'] ?? v['voice'] ?? v['identifier'] ?? '').toString();
    final locale = (v['locale'] ?? v['localeId'] ?? '').toString();
    return name.isNotEmpty ? '$name ${locale.isNotEmpty ? '($locale)' : ''}' : locale;
  }

  Widget _voicePickerButton() {
    if (_loading) return const CupertinoActivityIndicator();
    if (_voices.isEmpty) return const Text('No voice list available on this platform');
    int selectedIndex = _selectedVoice == null
        ? 0
        : _voices.indexWhere((v) => v['name'] == _selectedVoice!['name'] && v['locale'] == _selectedVoice!['locale']);
    selectedIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        await showCupertinoModalPopup(
          context: context,
          builder: (_) => Container(
            height: 275,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: Column(
              children: [
                Container(
                  height: 44,
                  color: CupertinoColors.systemGrey5.resolveFrom(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Text('Done'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(initialItem: selectedIndex),
                    itemExtent: 36,
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedVoice = {
                          'name': _voices[index]['name'] ?? '',
                          'locale': _voices[index]['locale'] ?? '',
                        };
                      });
                    },
                    children: _voices.map((v) => Center(child: Text(_voiceLabel(v)))).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _selectedVoice == null ? 'Choose a voice' : _voiceLabel(_selectedVoice!),
          style: const TextStyle(color: CupertinoColors.activeBlue, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _fitzKeySection() {
    final categories = [
      {'label': 'Person', 'key': 'fitz_person', 'default': 0xFFFFD600},
      {'label': 'Verb', 'key': 'fitz_verb', 'default': 0xFF43A047},
      {'label': 'Descriptor', 'key': 'fitz_descriptor', 'default': 0xFF1E88E5},
      {'label': 'Noun', 'key': 'fitz_noun', 'default': 0xFFEF6C00},
      {'label': 'Social', 'key': 'fitz_social', 'default': 0xFFE91E8C},
      {'label': 'Question', 'key': 'fitz_question', 'default': 0xFF8E24AA},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fitzgerald Key Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'These colors are used to categorize words on flashcards.',
          style: TextStyle(fontSize: 13, color: CupertinoColors.inactiveGray),
        ),
        const SizedBox(height: 12),
        ...categories.map((cat) {
          final colorValue = cat['default'] as int;
          final color = Color(colorValue);
          final label = cat['label'] as String;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.4), width: 2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Change', style: TextStyle(fontSize: 13, color: CupertinoColors.activeBlue)),
                  onPressed: () => _showColorPicker(label, cat['key'] as String, color),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showColorPicker(String label, String prefKey, Color current) {
    final presetColors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pick color for $label', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Done'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: presetColors.map((c) {
                  final isSelected = c.value == current.value;
                  return GestureDetector(
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(prefKey, c.value);
                      setState(() {});
                      if (mounted) Navigator.of(context).pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('card_count', _cardCount);
    if (mounted) {
      Navigator.of(context).pop({
        'voice': _selectedVoice,
        'rate': _rate,
        'volume': _volume,
        'cardCount': _cardCount,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voice selection', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _voicePickerButton(),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Volume: ${_volume.toStringAsFixed(2)}'),
              ),
              CupertinoSlider(
                value: _volume,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) => setState(() => _volume = v),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Flashcard Count: $_cardCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'More cards = smaller cards, less scrolling.',
                style: TextStyle(fontSize: 13, color: CupertinoColors.inactiveGray),
              ),
              CupertinoSlider(
                value: _cardCount.toDouble(),
                min: 6,
                max: 40,
                divisions: 34,
                onChanged: (v) => setState(() => _cardCount = v.round()),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              _fitzKeySection(),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: CupertinoColors.systemGrey,
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: _onSave,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}