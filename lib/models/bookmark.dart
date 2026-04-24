class Bookmark {
  final int? id;
  final int bookId;
  final int page;
  final String snippet;
  final DateTime createdAt;

  const Bookmark({
    this.id,
    required this.bookId,
    required this.page,
    required this.snippet,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'book_id': bookId,
    'page': page,
    'snippet': snippet,
    'created_at': createdAt.toIso8601String(),
  };

  static Bookmark fromMap(Map<String, dynamic> m) => Bookmark(
    id: m['id'] as int?,
    bookId: m['book_id'] as int,
    page: m['page'] as int,
    snippet: (m['snippet'] as String?) ?? '',
    createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
  );
}
