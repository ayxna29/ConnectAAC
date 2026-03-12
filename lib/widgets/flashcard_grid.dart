import 'package:flutter/material.dart';
import 'safe_svg.dart';
import 'package:string_similarity/string_similarity.dart';

enum FitzCategory { person, verb, descriptor, noun, social, question }

class FitzKey {
  final FitzCategory category;
  FitzKey(this.category);

  static FitzKey resolve(String word, Map<String, String>? backendFitz) {
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
    final lower = word.toLowerCase();
    const people = {'i','me','my','you','he','she','we','they','him','her','us','them','mom','dad','friend','teacher'};
    const social = {'yes','no','please','thanks','thank','sorry','hello','bye','more','done','stop','help','again','wait','ok','okay'};
    const questions = {'what','where','who','when','why','how','which'};
    if (questions.contains(lower)) return FitzKey(FitzCategory.question);
    if (people.contains(lower))    return FitzKey(FitzCategory.person);
    if (social.contains(lower))    return FitzKey(FitzCategory.social);
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
      case FitzCategory.social:     return const Color(0xFFE91E8C);
      case FitzCategory.question:   return const Color(0xFF8E24AA);
    }
  }

  Color get bgColor {
    switch (category) {
      case FitzCategory.person:     return const Color(0xFFFFFDE7);
      case FitzCategory.verb:       return const Color(0xFFF1F8E9);
      case FitzCategory.descriptor: return const Color(0xFFE3F2FD);
      case FitzCategory.noun:       return const Color(0xFFFFF3E0);
      case FitzCategory.social:     return const Color(0xFFFCE4EC);
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
    this.maxCards = 12,
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
  final Map<String, String>? wordToFitz;
  final int maxCards;

  static const double _matchThreshold = 0.5;

  String? _findBestMatch(String word) {
    if (preMapped != null && preMapped!.containsKey(word)) return preMapped![word];
    final pool = availableFilenames ?? const <String>[];
    if (pool.isEmpty) return null;
    var bestScore = 0.0;
    String? bestFile;
    final lowerWord = word.toLowerCase();
    for (final file in pool) {
      final nameOnly = file.toLowerCase().replaceAll(RegExp(r'\.svg$'), '');
      final score = StringSimilarity.compareTwoStrings(lowerWord, nameOnly);
      if (score > bestScore) { bestScore = score; bestFile = file; }
    }
    return bestScore >= _matchThreshold ? bestFile : null;
  }

  @override
  Widget build(BuildContext context) {
    final items = words ?? const <String>[];
    final mapped = items.map((w) => MapEntry(w, _findBestMatch(w))).toList();

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

    final visible = ordered.take(maxCards).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight;

        int cols = 2;
        int rows = (visible.length / cols).ceil();
        for (int c = 2; c <= 10; c++) {
          final r = (visible.length / c).ceil();
          final cardW = (totalWidth - (c + 1) * 10) / c;
          final cardH = (totalHeight - (r + 1) * 10) / r;
          if (cardW >= 80 && cardH >= 80) {
            cols = c;
            rows = r;
          }
        }

        final cardW = (totalWidth - (cols + 1) * 10) / cols;
        final cardH = (totalHeight - (rows + 1) * 10) / rows;
        final cardSize = cardW < cardH ? cardW : cardH;

        final iconSize = (cardSize * 0.45).clamp(24.0, 100.0);
        final fontSize = (cardSize * 0.14).clamp(9.0, 18.0);
        final borderRadius = (cardSize * 0.1).clamp(6.0, 14.0);

        return GridView.count(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(10),
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.0,
          children: visible.map((entry) {
            final word = entry.key;
            final filename = entry.value;

            // Treat blank.svg as no image — show word placeholder instead
            final isBlank = filename == null || filename.toLowerCase() == 'blank.svg';
            final assetPath = !isBlank
                ? 'assets/mulberry-symbols/EN-symbols/$filename'
                : null;

            final cardId = wordToCardId?[word];
            final isFavorite = cardId != null && favorites != null && favorites!.contains(cardId);
            final fileTags = (filename != null && tags != null) ? tags![filename] ?? [] : <String>[];
            final fitz = FitzKey.resolve(word, wordToFitz);
            final border = fitz.borderColor;
            final bg = fitz.bgColor;

            return GestureDetector(
              onTap: () => onCardTap?.call(word),
              onLongPress: () => onRate?.call(word, filename),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(color: border, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: border.withOpacity(0.18), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Center(
                              child: assetPath != null
                                  ? SafeSvg(assetPath: assetPath, fit: BoxFit.contain, height: iconSize)
                                  : Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: border.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          word,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: (fontSize + 14).clamp(18.0, 48.0),
                                            fontWeight: FontWeight.bold,
                                            color: border.withOpacity(0.75),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            word,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: GestureDetector(
                        onTap: () {
                          if (onToggleFavorite != null && cardId != null) onToggleFavorite!(cardId);
                        },
                        child: CircleAvatar(
                          radius: (cardSize * 0.1).clamp(10.0, 16.0),
                          backgroundColor: Colors.white70,
                          child: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.black38,
                            size: (cardSize * 0.12).clamp(10.0, 18.0),
                          ),
                        ),
                      ),
                    ),
                    if (fileTags.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            fileTags.take(2).map((t) => '#$t').join(' '),
                            style: const TextStyle(fontSize: 9, color: Colors.black54),
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