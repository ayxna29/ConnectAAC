class Flashcard {
  final String phrase;
  final String svgAssetPath;
  bool isFavorite;

  Flashcard({required this.phrase, required this.svgAssetPath, this.isFavorite = false});
}