class ReaderNote {
  final int? id;
  final int bookId;
  final int page;
  final String selectedText;
  final String noteText;
  final DateTime createdAt;

  const ReaderNote({
    this.id,
    required this.bookId,
    required this.page,
    required this.selectedText,
    required this.noteText,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'book_id': bookId,
    'page': page,
    'selected_text': selectedText,
    'note_text': noteText,
    'created_at': createdAt.toIso8601String(),
  };

  static ReaderNote fromMap(Map<String, dynamic> m) => ReaderNote(
    id: m['id'] as int?,
    bookId: m['book_id'] as int,
    page: m['page'] as int,
    selectedText: (m['selected_text'] as String?) ?? '',
    noteText: (m['note_text'] as String?) ?? '',
    createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
  );
}
