import 'package:flutter/cupertino.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SettingsPage extends StatefulWidget {
  final Map<String, String>? initialVoice;
  final double initialRate;
  final double initialVolume;

  const SettingsPage({
    super.key,
    this.initialVoice,
    required this.initialRate,
    required this.initialVolume,
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _rate = widget.initialRate;
    _volume = widget.initialVolume;
    _selectedVoice = widget.initialVoice;
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final raw = await _localTts.getVoices;
      if (raw != null && raw is List) {
        _voices = raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {
      _voices = [];
    }
    setState(() => _loading = false);
  }

  String _voiceLabel(Map<String, dynamic> v) {
    final name = (v['name'] ?? v['voice'] ?? v['identifier'] ?? '').toString();
    final locale = (v['locale'] ?? v['localeId'] ?? '').toString();
    return name.isNotEmpty
        ? '$name ${locale.isNotEmpty ? '($locale)' : ''}'
        : locale;
  }

  Widget _voicePickerButton() {
    if (_loading) return const CupertinoActivityIndicator();
    if (_voices.isEmpty) {
      return const Text('No voice list available on this platform');
    }
    // Find selected index
    int selectedIndex = _selectedVoice == null
        ? 0
        : _voices.indexWhere((v) =>
            v['name'] == _selectedVoice!['name'] &&
            v['locale'] == _selectedVoice!['locale']);
    selectedIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        await showCupertinoModalPopup(
          context: context,
          builder: (_) {
            return Container(
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
                      scrollController:
                          FixedExtentScrollController(initialItem: selectedIndex),
                      itemExtent: 36,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedVoice = {
                            'name': _voices[index]['name'] ?? '',
                            'locale': _voices[index]['locale'] ?? '',
                          };
                        });
                      },
                      children: _voices
                          .map((v) => Center(child: Text(_voiceLabel(v))))
                          .toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _selectedVoice == null
              ? 'Choose a voice'
              : _voiceLabel(_selectedVoice!),
          style: const TextStyle(
            color: CupertinoColors.activeBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _onSave() {
    Navigator.of(context).pop(
        {'voice': _selectedVoice, 'rate': _rate, 'volume': _volume});
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Voice selection',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              _voicePickerButton(),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Speed: ${_rate.toStringAsFixed(2)}'),
              ),
              CupertinoSlider(
                value: _rate,
                min: 0.2,
                max: 1.2,
                divisions: 50,
                onChanged: (v) => setState(() => _rate = v),
              ),
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
              const Spacer(),
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
            ],
          ),
        ),
      ),
    );
  }
}

