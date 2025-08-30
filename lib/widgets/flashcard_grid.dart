import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:flutter/services.dart';

/// FlashcardGrid shows a grid of flashcards for a test word list.
/// Each card shows the matched SVG (if any) and the word label.
/// Tapping a card calls the onCardTap callback (word string).
class FlashcardGrid extends StatelessWidget {
  const FlashcardGrid({super.key, this.words, this.onCardTap});

  // callback invoked when a card is tapped
  final ValueChanged<String>? onCardTap;

  // Hardcoded test words for now.
  static const List<String> _defaultTestWords = [
    "airplane",
    "car",
    "bicycle",
    "dog",
  ];

  // Example available filenames in assets/mulberry-symbols/EN-symbols/
  static const List<String> _availableFilenames = [
    "aeroplane.svg",
    "car.svg",
    "bicycle.svg",
    "dog.svg",
  ];

  final List<String>? words;
  static const double _matchThreshold = 0.5;

  // AssetManifest cache (shared across instances).
  static Future<Map<String, dynamic>>? _manifestFuture;

  String? _findBestMatch(String word) {
    var bestScore = 0.0;
    String? bestFile;
    final lowerWord = word.toLowerCase();
    for (final file in _availableFilenames) {
      final nameOnly = file.toLowerCase().replaceAll(RegExp(r'\.svg$'), '');
      final score = StringSimilarity.compareTwoStrings(lowerWord, nameOnly);
      if (score > bestScore) {
        bestScore = score;
        bestFile = file;
      }
    }
    if (bestScore >= _matchThreshold) return bestFile;
    return null;
  }

  Future<bool> _assetExists(String assetPath) async {
    try {
      _manifestFuture ??= rootBundle.loadString('AssetManifest.json').then((s) {
        final map = json.decode(s) as Map<String, dynamic>;
        return map;
      });
      final manifest = await _manifestFuture!;
      if (manifest.containsKey(assetPath)) return true;
      final withoutAssets = assetPath.replaceFirst(RegExp(r'^assets/'), '');
      if (manifest.containsKey(withoutAssets)) return true;
      if (!assetPath.startsWith('assets/')) {
        final withAssets = 'assets/$assetPath';
        if (manifest.containsKey(withAssets)) return true;
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to read AssetManifest.json: $e');
      return false;
    }
  }

  // Requirement: signature exactly buildFlashcard(String word)
  Widget buildFlashcard(String word) {
    final match = _findBestMatch(word);
    final assetPath = match != null
        ? 'assets/mulberry-symbols/EN-symbols/$match'
        : null;

    // Wrap card in GestureDetector so taps are handled and forwarded.
    return GestureDetector(
      onTap: () {
        if (onCardTap != null) onCardTap!(word);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          // Column places image above with label near bottom
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 6),
              // Larger image area for autism-friendly layout
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    // let height grow within Expanded
                    child: assetPath != null
                        ? FutureBuilder<bool>(
                            future: _assetExists(assetPath),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                );
                              }
                              final exists = snapshot.data == true;
                              if (exists) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8.0, horizontal: 8.0),
                                  child: SvgPicture.asset(
                                    assetPath,
                                    fit: BoxFit.contain,
                                  ),
                                );
                              }
                              return Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 56,
                                    color: Colors.black26,
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.help_outline,
                                size: 56,
                                color: Colors.black26,
                              ),
                            ),
                          ),
                  ),
                ),
              ),

              // Label area pushed towards bottom, larger & bolder
              const SizedBox(height: 8),
              Text(
                word,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20, // larger label
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = words ?? _defaultTestWords;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = (width / 260).floor();
        if (crossAxisCount < 2) crossAxisCount = 2;
        return GridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: items.map((w) => buildFlashcard(w)).toList(),
        );
      },
    );
  }
}
