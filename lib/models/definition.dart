class Definition {
  final String partOfSpeech;
  final String text;         // English definition
  final String chineseText;  // Chinese translation of this specific sense
  final String example;

  const Definition({
    required this.partOfSpeech,
    required this.text,
    this.chineseText = '',
    this.example = '',
  });

  Definition copyWith({String? chineseText}) => Definition(
        partOfSpeech: partOfSpeech,
        text: text,
        chineseText: chineseText ?? this.chineseText,
        example: example,
      );
}

/// Result from a single custom dictionary source.
class DictResult {
  final String name;    // DictSource.name
  final String content; // Raw HTML content from the dictionary
  final bool isHtml;    // true = render as HTML, false = plain text

  const DictResult({required this.name, required this.content, this.isHtml = false});
}

class WordLookupResult {
  final String word;
  final String phonetic;
  final String chineseMeaning;
  final List<Definition> definitions;   // from FreeDictionary API (with chineseText)
  final List<DictResult> dictResults;   // from custom dicts (all enabled)
  final bool found;

  const WordLookupResult({
    required this.word,
    this.phonetic = '',
    this.chineseMeaning = '',
    this.definitions = const [],
    this.dictResults = const [],
    this.found = false,
  });
}
