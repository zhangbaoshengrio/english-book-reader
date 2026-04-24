import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'reader_screen.dart';
import 'vocab_screen.dart';
import 'settings_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  List<Book> _books = [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final books = await DatabaseService.getAllBooks();
    if (mounted) {
      setState(() {
        _books = books;
        _loading = false;
      });
    }
  }

  Future<void> _addBook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final name = result.files.single.name;
    final title = name
        .replaceAll(RegExp(r'\.(txt|epub)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim();

    setState(() => _adding = true);
    try {
      final paragraphs = await BookParser.parse(path);
      final totalPages = BookParser.pageCount(paragraphs.length);
      final book = Book(
        title: title,
        filePath: path,
        totalPages: totalPages,
        addedAt: DateTime.now(),
      );
      final saved = await DatabaseService.upsertBook(book);
      if (!mounted) return;
      _openBook(saved, paragraphs);
      await _loadBooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openExistingBook(Book book) async {
    if (!File(book.filePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found. Please re-import.')),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      final paragraphs = await BookParser.parse(book.filePath);
      if (!mounted) return;
      _openBook(book, paragraphs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _openBook(Book book, List<String> paragraphs) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(book: book, paragraphs: paragraphs),
      ),
    ).then((_) => _loadBooks()); // refresh progress on return
  }

  Future<void> _deleteBook(Book book) async {
    await DatabaseService.deleteBook(book.id!);
    setState(() => _books.removeWhere((b) => b.id == book.id));
  }

  // Generate consistent color from title
  Color _bookColor(String title) {
    const colors = [
      Color(0xFF5C6BC0),
      Color(0xFF26A69A),
      Color(0xFF42A5F5),
      Color(0xFFAB47BC),
      Color(0xFFEF5350),
      Color(0xFF66BB6A),
      Color(0xFFFFA726),
      Color(0xFFEC407A),
    ];
    return colors[title.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.groupedBg,
      appBar: AppBar(
        title: const Text('书架'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.star_rounded),
            color: AppTheme.primary,
            tooltip: '词汇本',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VocabScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            color: AppTheme.primary,
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (_books.isEmpty)
            _buildEmpty()
          else
            _buildList(),
          if (_adding)
            const ColoredBox(
              color: Color(0x44000000),
              child: Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _addBook,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Book'),
        elevation: 2,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 72, color: AppTheme.textTertiary),
          const SizedBox(height: 16),
          const Text('No books yet',
              style:
                  TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          const Text('Tap "Add Book" to import a .txt or .epub file',
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _books.length,
      itemBuilder: (_, i) => _BookCard(
        book: _books[i],
        color: _bookColor(_books[i].title),
        onTap: () => _openExistingBook(_books[i]),
        onDelete: () => _deleteBook(_books[i]),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.color,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final fileExists = File(book.filePath).existsSync();
    final pct = (book.progress * 100).round();

    return Dismissible(
      key: ValueKey(book.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: AppTheme.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              // Book spine / cover
              Container(
                width: 56,
                height: 90,
                decoration: BoxDecoration(
                  color: fileExists ? color : Colors.grey.shade400,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14)),
                ),
                child: Center(
                  child: Text(
                    book.title.isNotEmpty
                        ? book.title[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // Book info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (book.totalPages > 0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: book.progress,
                            backgroundColor: const Color(0xFFE8E8E8),
                            color: fileExists ? color : Colors.grey,
                            minHeight: 3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.totalPages > 0
                              ? 'Page ${book.lastPage + 1} / ${book.totalPages}  ($pct%)'
                              : 'Not started',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                      if (!fileExists)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'File not found',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
