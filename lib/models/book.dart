class Book {
  final int? id;
  final String title;
  final String filePath;
  final int lastPage;
  final int totalPages;
  final DateTime addedAt;

  const Book({
    this.id,
    required this.title,
    required this.filePath,
    this.lastPage = 0,
    this.totalPages = 0,
    required this.addedAt,
  });

  double get progress =>
      totalPages > 0 ? (lastPage / totalPages).clamp(0.0, 1.0) : 0.0;

  Book copyWith({int? id, int? lastPage, int? totalPages}) => Book(
        id: id ?? this.id,
        title: title,
        filePath: filePath,
        lastPage: lastPage ?? this.lastPage,
        totalPages: totalPages ?? this.totalPages,
        addedAt: addedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'file_path': filePath,
        'last_page': lastPage,
        'total_pages': totalPages,
        'added_at': addedAt.millisecondsSinceEpoch,
      };

  static Book fromMap(Map<String, dynamic> m) => Book(
        id: m['id'] as int?,
        title: m['title'] as String,
        filePath: m['file_path'] as String,
        lastPage: (m['last_page'] as int?) ?? 0,
        totalPages: (m['total_pages'] as int?) ?? 0,
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );
}
