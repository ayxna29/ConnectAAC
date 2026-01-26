class VocabCard {
  final String id;
  final String word;
  final String? assetFilename;
  final int layer; // 1-5
  final bool isSkeleton;

  VocabCard({
    required this.id,
    required this.word,
    this.assetFilename,
    required this.layer,
    this.isSkeleton = false,
  });

  factory VocabCard.skeleton(int layer) {
    return VocabCard(
      id: 'skeleton_${DateTime.now().millisecondsSinceEpoch}',
      word: '',
      layer: layer,
      isSkeleton: true,
    );
  }

  factory VocabCard.fromJson(Map<String, dynamic> json, int layer) {
    return VocabCard(
      id: json['id']?.toString() ?? '',
      word: json['word']?.toString() ?? '',
      assetFilename: json['asset_filename'],
      layer: layer,
    );
  }
}

class PromptVocabState {
  final String promptId;
  final List<VocabCard> promptCore; // Layer 1
  final List<VocabCard> modifiers; // Layer 2
  final List<VocabCard> grammar; // Layer 3
  final List<VocabCard> personalized; // Layer 4
  final List<VocabCard> aiExpanded; // Layer 5

  final bool isLoadingPersonalized;
  final bool isLoadingAI;

  PromptVocabState({
    required this.promptId,
    this.promptCore = const [],
    this.modifiers = const [],
    this.grammar = const [],
    this.personalized = const [],
    this.aiExpanded = const [],
    this.isLoadingPersonalized = false,
    this.isLoadingAI = false,
  });

  List<VocabCard> get allCards {
    return [
      ...promptCore,
      ...modifiers,
      ...grammar,
      ...personalized,
      ...aiExpanded,
    ];
  }

  PromptVocabState copyWith({
    List<VocabCard>? promptCore,
    List<VocabCard>? modifiers,
    List<VocabCard>? grammar,
    List<VocabCard>? personalized,
    List<VocabCard>? aiExpanded,
    bool? isLoadingPersonalized,
    bool? isLoadingAI,
  }) {
    return PromptVocabState(
      promptId: promptId,
      promptCore: promptCore ?? this.promptCore,
      modifiers: modifiers ?? this.modifiers,
      grammar: grammar ?? this.grammar,
      personalized: personalized ?? this.personalized,
      aiExpanded: aiExpanded ?? this.aiExpanded,
      isLoadingPersonalized:
          isLoadingPersonalized ?? this.isLoadingPersonalized,
      isLoadingAI: isLoadingAI ?? this.isLoadingAI,
    );
  }
}

class PromptContext {
  final String id;
  final String name;
  final String description;

  PromptContext({
    required this.id,
    required this.name,
    required this.description,
  });
}
