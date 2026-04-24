import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'reader_screen.dart';
import 'vocab_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
    );
    if (result == null || result.files.single.path == null) return;

    final path  = result.files.single.path!;
    final name  = result.files.single.name;
    final title = name
        .replaceAll(RegExp(r'\.(txt|epub)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim();

    setState(() => _loading = true);
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(book: saved, paragraphs: paragraphs),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.groupedBg,
      appBar: AppBar(
        title: const Text('English Reader'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.star_rounded),
            color: AppTheme.primary,
            tooltip: 'Vocabulary',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VocabScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Book icon
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        size: 58,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 28),

                    const Text(
                      'English Book Reader',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Open a .txt or .epub book.\nTap any word to look it up and save it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 44),

                    // Open book button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Open Book'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vocabulary button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VocabScreen()),
                        ),
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('My Vocabulary'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
