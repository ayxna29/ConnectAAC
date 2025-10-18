import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:string_similarity/string_similarity.dart';

class FlashcardGrid extends StatelessWidget {
  const FlashcardGrid({
    super.key,
    this.words,
    this.onCardTap,
    this.favorites,
    this.onToggleFavorite,
    this.tags,
    this.availableFilenames,
    this.preMapped, // optional explicit mapping word -> filename
    this.wordToCardId, // optional mapping word -> card ID
    this.onRate,
  });

  final List<String>? words; // list of words/answers to display
  final ValueChanged<String>? onCardTap;
  final ValueChanged<String>? onToggleFavorite; // receives card ID
  final Set<String>? favorites; // set of card IDs (not filenames)
  final Map<String, List<String>>? tags; // filename -> tags
  final List<String>? availableFilenames; // injected list of symbol filenames
  final Map<String, String>? preMapped; // if provided, bypass fuzzy per word
  final Map<String, String>? wordToCardId; // word -> card ID mapping
  final void Function(String word, String? filename)? onRate; // rating callback

  static const double _matchThreshold = 0.5;

  String? _findBestMatch(String word) {
    if (preMapped != null && preMapped!.containsKey(word)) {
      return preMapped![word];
    }
    final pool = availableFilenames ?? const <String>[];
    if (pool.isEmpty) return null;
    var bestScore = 0.0;
    String? bestFile;
    final lowerWord = word.toLowerCase();
    for (final file in pool) {
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
    final items = words ?? const <String>[];

    // Build list of tuples (word, matchedFilename)
    final mapped = items.map((w) {
      final match = _findBestMatch(w);
      return MapEntry(w, match);
    }).toList();

    // Reorder so favorites appear first (if favorites set provided)
    List<MapEntry<String, String?>> ordered;
    if (favorites != null && favorites!.isNotEmpty && wordToCardId != null) {
      final fav = <MapEntry<String, String?>>[];
      final other = <MapEntry<String, String?>>[];
      for (final e in mapped) {
        final cardId = wordToCardId![e.key]; // get card ID for this word
        if (cardId != null && favorites!.contains(cardId)) {
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
            final cardId = wordToCardId?[word]; // get card ID for this word
            final isFavorite =
                cardId != null &&
                favorites != null &&
                favorites!.contains(cardId); // check by card ID
            final fileTags = (filename != null && tags != null)
                ? tags![filename] ?? []
                : <String>[];

            return GestureDetector(
              onTap: () {
                if (onCardTap != null) onCardTap!(word);
              },
              onLongPress: () {
                if (onRate != null) onRate!(word, filename);
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
                          // toggle favorite for this flashcard (pass card ID)
                          if (onToggleFavorite != null && cardId != null) {
                            onToggleFavorite!(cardId);
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
                            color: Colors.black.withAlpha(15),
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
