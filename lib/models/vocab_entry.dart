class VocabEntry {
  final int? id;
  final String word;
  final String phonetic;
  final String partOfSpeech;
  final String definition;       // English definition
  final String chineseMeaning;   // Chinese translation
  final String sentence;
  final String source;
  final DateTime addedAt;

  VocabEntry({
    this.id,
    required this.word,
    required this.definition,
    this.phonetic = '',
    this.partOfSpeech = '',
    this.chineseMeaning = '',
    this.sentence = '',
    this.source = '',
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'word':            word,
    'phonetic':        phonetic,
    'definition':      definition,
    'chinese_meaning': chineseMeaning,
    'part_of_speech':  partOfSpeech,
    'sentence':        sentence,
    'source':          source,
    'added_at':        addedAt.toIso8601String(),
  };

  factory VocabEntry.fromMap(Map<String, dynamic> m) => VocabEntry(
    id:             m['id'] as int?,
    word:           m['word'] as String,
    phonetic:       (m['phonetic']        as String?) ?? '',
    definition:     (m['definition']      as String?) ?? '',
    chineseMeaning: (m['chinese_meaning'] as String?) ?? '',
    partOfSpeech:   (m['part_of_speech']  as String?) ?? '',
    sentence:       (m['sentence']        as String?) ?? '',
    source:         (m['source']          as String?) ?? '',
    addedAt:        m['added_at'] != null
                      ? DateTime.tryParse(m['added_at'] as String) ?? DateTime.now()
                      : DateTime.now(),
  );
}
