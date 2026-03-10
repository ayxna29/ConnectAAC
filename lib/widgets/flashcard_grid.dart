import 'package:flutter/material.dart';
import 'safe_svg.dart';
import 'package:string_similarity/string_similarity.dart';

enum FitzCategory { person, verb, descriptor, noun, social, question }

class FitzKey {
  final FitzCategory category;
  FitzKey(this.category);

  static FitzKey resolve(String word, Map<String, String>? backendFitz) {
    // Try backend string value first
    if (backendFitz != null && backendFitz.containsKey(word)) {
      switch (backendFitz[word]) {
        case 'person':     return FitzKey(FitzCategory.person);
        case 'verb':       return FitzKey(FitzCategory.verb);
        case 'descriptor': return FitzKey(FitzCategory.descriptor);
        case 'noun':       return FitzKey(FitzCategory.noun);
        case 'social':     return FitzKey(FitzCategory.social);
        case 'question':   return FitzKey(FitzCategory.question);
      }
    }
    // Fallback: classify from the word itself
    final lower = word.toLowerCase();
    const people = {'i','me','my','you','he','she','we','they','him','her','us','them','mom','dad','friend','teacher'};
    const social = {'yes','no','please','thanks','thank','sorry','hello','bye','more','done','stop','help','again','wait','ok','okay'};
    const questions = {'what','where','who','when','why','how','which'};
    if (questions.contains(lower)) return FitzKey(FitzCategory.question);
    if (people.contains(lower))   return FitzKey(FitzCategory.person);
    if (social.contains(lower))   return FitzKey(FitzCategory.social);
    if (lower.endsWith('ing') && lower.length > 4) return FitzKey(FitzCategory.verb);
    if (lower.endsWith('ed')  && lower.length > 3) return FitzKey(FitzCategory.verb);
    const verbs = {'want','need','feel','am','is','are','was','have','has','do','did','go','eat','drink','hurt','hurts','help','like','love','hate','see','hear','sleep','run','walk','play','get','give','take','make','come','can','will','dont','cant'};
    if (verbs.contains(lower)) return FitzKey(FitzCategory.verb);
    const descriptors = {'good','bad','happy','sad','tired','angry','scared','sick','okay','fine','sore','better','worse','big','small','hot','cold','fast','slow','loud','quiet','hungry','thirsty','full','ready','clean','dirty','old','new','red','blue','green','yellow','purple','orange','pink','brown','black','white'};
    if (descriptors.contains(lower)) return FitzKey(FitzCategory.descriptor);
    return FitzKey(FitzCategory.noun);
  }

  Color get borderColor {
    switch (category) {
      case FitzCategory.person:     return const Color(0xFFFFD600);
      case FitzCategory.verb:       return const Color(0xFF43A047);
      case FitzCategory.descriptor: return const Color(0xFF1E88E5);
      case FitzCategory.noun:       return const Color(0xFFEF6C00);
      case FitzCategory.social:     return const Color(0xFF9E9E9E);
      case FitzCategory.question:   return const Color(0xFF8E24AA);
    }
  }

  Color get bgColor {
    switch (category) {
      case FitzCategory.person:     return const Color(0xFFFFFDE7);
      case FitzCategory.verb:       return const Color(0xFFF1F8E9);
      case FitzCategory.descriptor: return const Color(0xFFE3F2FD);
      case FitzCategory.noun:       return const Color(0xFFFFF3E0);
      case FitzCategory.social:     return const Color(0xFFF5F5F5);
      case FitzCategory.question:   return const Color(0xFFF3E5F5);
    }
  }
}

class FlashcardGrid extends StatelessWidget {
  const FlashcardGrid({
    super.key,
    this.words,
    this.onCardTap,
    this.favorites,
    this.onToggleFavorite,
    this.tags,
    this.availableFilenames,
    this.preMapped,
    this.wordToCardId,
    this.onRate,
    this.wordToFitz,
  });

  final List<String>? words;
  final ValueChanged<String>? onCardTap;
  final ValueChanged<String>? onToggleFavorite;
  final Set<String>? favorites;
  final Map<String, List<String>>? tags;
  final List<String>? availableFilenames;
  final Map<String, String>? preMapped;
  final Map<String, String>? wordToCardId;
  final void Function(String word, String? filename)? onRate;
  final Map<String, String>? wordToFitz; // word -> fitz string from backend

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

    final mapped = items.map((w) {
      final match = _findBestMatch(w);
      return MapEntry(w, match);
    }).toList();

    List<MapEntry<String, String?>> ordered;
    if (favorites != null && favorites!.isNotEmpty && wordToCardId != null) {
      final fav = <MapEntry<String, String?>>[];
      final other = <MapEntry<String, String?>>[];
      for (final e in mapped) {
        final cardId = wordToCardId![e.key];
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
            final filename = entry.value;
            final assetPath = filename != null
                ? 'assets/mulberry-symbols/EN-symbols/$filename'
                : null;
            final cardId = wordToCardId?[word];
            final isFavorite = cardId != null &&
                favorites != null &&
                favorites!.contains(cardId);
            final fileTags = (filename != null && tags != null)
                ? tags![filename] ?? []
                : <String>[];

            final fitz = FitzKey.resolve(word, wordToFitz);
            final border = fitz.borderColor;
            final bg = fitz.bgColor;

            return GestureDetector(
              onTap: () => onCardTap?.call(word),
              onLongPress: () => onRate?.call(word, filename),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: 3.5),
                  boxShadow: [
                    BoxShadow(
                      color: border.withOpacity(0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
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
                                            vertical: 8.0, horizontal: 8.0),
                                        child: SafeSvg(
                                          assetPath: assetPath,
                                          fit: BoxFit.contain,
                                          height: 120,
                                        ),
                                      )
                                    : Container(
                                        height: 120,
                                        decoration: BoxDecoration(
                                          color: border.withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.help_outline,
                                            size: 48,
                                            color: border.withOpacity(0.35),
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

                    // Tags bottom-left
                    if (fileTags.isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            fileTags.take(2).map((t) => '#$t').join(' '),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
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