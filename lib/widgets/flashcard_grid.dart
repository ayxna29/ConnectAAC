import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:flutter/services.dart';

class FlashcardGrid extends StatelessWidget {
  const FlashcardGrid({
    super.key,
    this.words,
    this.onCardTap,
    this.favorites,
    this.onToggleFavorite,
    this.tags,
  });

  final List<String>? words;
  final ValueChanged<String>? onCardTap;
  final ValueChanged<String>? onToggleFavorite;
  final Set<String>? favorites; // set of filenames (e.g. 'dog.svg')
  final Map<String, List<String>>? tags; // filename -> tags

  static const List<String> _availableFilenames = [
    "aeroplane.svg",
    "car.svg",
    "bicycle.svg",
    "dog.svg",
  ];

  static const double _matchThreshold = 0.5;

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

  @override
  Widget build(BuildContext context) {
    final items = words ?? <String>['airplane', 'car', 'bicycle', 'dog'];

    // Build list of tuples (word, matchedFilename)
    final mapped = items.map((w) {
      final match = _findBestMatch(w);
      return MapEntry(w, match);
    }).toList();

    // Reorder so favorites appear first (if favorites set provided)
    List<MapEntry<String, String?>> ordered;
    if (favorites != null && favorites!.isNotEmpty) {
      final fav = <MapEntry<String, String?>>[];
      final other = <MapEntry<String, String?>>[];
      for (final e in mapped) {
        if (e.value != null && favorites!.contains(e.value!)) {
          fav.add(e);
        } else {
          other.add(e);
        }
      }
      ordered = [...fav, ...other];
    } else {
      ordered = mapped;
    }

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
          children: ordered.map((entry) {
            final word = entry.key;
            final filename = entry.value; // may be null
            final assetPath = (filename != null)
                ? 'assets/mulberry-symbols/EN-symbols/$filename'
                : null;
            final isFavorite =
                filename != null &&
                favorites != null &&
                favorites!.contains(filename);
            final fileTags = (filename != null && tags != null)
                ? tags![filename] ?? []
                : <String>[];

            return GestureDetector(
              onTap: () {
                if (onCardTap != null) onCardTap!(word);
              },
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(height: 6),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: double.infinity,
                                child: assetPath != null
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8.0,
                                          horizontal: 8.0,
                                        ),
                                        child: SvgPicture.asset(
                                          assetPath,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : Container(
                                        height: 120,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.help_outline,
                                            size: 48,
                                            color: Colors.black26,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            word,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // Favorite toggle top-right
                    Positioned(
                      right: 6,
                      top: 6,
                      child: GestureDetector(
                        onTap: () {
                          // toggle favorite for this flashcard (pass filename if available else word)
                          if (onToggleFavorite != null) {
                            onToggleFavorite!(filename ?? word);
                          }
                        },
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white70,
                          child: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.black38,
                          ),
                        ),
                      ),
                    ),

                    // Small tag indicators bottom-left
                    if (fileTags.isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            fileTags.take(2).map((t) => '#$t').join(' '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
