import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/vocab_entry.dart';
import '../models/book.dart';
import '../models/dict_source.dart';
import '../models/bookmark.dart';
import '../models/reader_note.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, 'vocab.db'),
      version: 9,
      onCreate: (db, _) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL UNIQUE,
            last_page INTEGER DEFAULT 0,
            total_pages INTEGER DEFAULT 0,
            added_at INTEGER NOT NULL
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS custom_dicts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            file_path TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            enabled INTEGER DEFAULT 1,
            added_at INTEGER NOT NULL
          )''');
          try {
            await db.execute('ALTER TABLE dict_cache ADD COLUMN chinese TEXT DEFAULT ""');
          } catch (_) {}
        }
        if (oldV < 3) {
          try {
            await db.execute('ALTER TABLE dict_cache ADD COLUMN def_cn_json TEXT DEFAULT ""');
          } catch (_) {}
        }
        if (oldV < 4) {
          try {
            await db.execute('ALTER TABLE custom_dicts ADD COLUMN sort_order INTEGER DEFAULT 999');
          } catch (_) {}
          // Assign sequential sort_order to existing custom dicts
          final existing = await db.query('custom_dicts',
              where: 'type != ?', whereArgs: ['builtin'], orderBy: 'added_at ASC');
          for (var i = 0; i < existing.length; i++) {
            await db.update('custom_dicts', {'sort_order': i + 10},
                where: 'id = ?', whereArgs: [existing[i]['id']]);
          }
        }
        if (oldV < 6) {
          // Remove all built-in dict entries
          await db.delete('custom_dicts', where: 'type = ?', whereArgs: ['builtin']);
        }
        if (oldV < 7) {
          try {
            await db.execute('ALTER TABLE vocabulary ADD COLUMN phonetic TEXT DEFAULT ""');
          } catch (_) {}
        }
        if (oldV < 8) {
          try {
            await db.execute('ALTER TABLE vocabulary ADD COLUMN chinese_meaning TEXT DEFAULT ""');
          } catch (_) {}
        }
        if (oldV < 9) {
          await db.execute('''CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            page INTEGER NOT NULL,
            snippet TEXT DEFAULT '',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )''');
          await db.execute('''CREATE TABLE IF NOT EXISTS reader_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            page INTEGER NOT NULL,
            selected_text TEXT DEFAULT '',
            note_text TEXT DEFAULT '',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )''');
        }
      },
    );
  }

  static Future<void> _createAllTables(Database db) async {
    await db.execute('''CREATE TABLE vocabulary (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      word          TEXT NOT NULL,
      phonetic      TEXT DEFAULT '',
      definition    TEXT DEFAULT '',
      chinese_meaning TEXT DEFAULT '',
      part_of_speech TEXT DEFAULT '',
      sentence      TEXT DEFAULT '',
      source        TEXT DEFAULT '',
      added_at      TEXT DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute('''CREATE TABLE dict_cache (
      word          TEXT PRIMARY KEY,
      json_data     TEXT NOT NULL,
      chinese       TEXT DEFAULT '',
      def_cn_json   TEXT DEFAULT '',
      cached_at     TEXT DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute('''CREATE TABLE books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      file_path TEXT NOT NULL UNIQUE,
      last_page INTEGER DEFAULT 0,
      total_pages INTEGER DEFAULT 0,
      added_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE custom_dicts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      file_path TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL,
      enabled INTEGER DEFAULT 1,
      sort_order INTEGER DEFAULT 999,
      added_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id INTEGER NOT NULL,
      page INTEGER NOT NULL,
      snippet TEXT DEFAULT '',
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )''');
    await db.execute('''CREATE TABLE reader_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id INTEGER NOT NULL,
      page INTEGER NOT NULL,
      selected_text TEXT DEFAULT '',
      note_text TEXT DEFAULT '',
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )''');
  }

  // ── Vocabulary ────────────────────────────────────────────────────────────

  static Future<int> addOrUpdateWord(VocabEntry entry) async {
    final db = await _database;
    final exists = await db.query(
      'vocabulary',
      columns: ['id'],
      where: 'LOWER(word) = LOWER(?)',
      whereArgs: [entry.word],
    );
    if (exists.isNotEmpty) {
      final id = exists.first['id'] as int;
      await db.update('vocabulary', entry.toMap(),
          where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('vocabulary', entry.toMap());
  }

  static Future<int> addWord(VocabEntry entry) async {
    final db = await _database;
    final exists = await db.query(
      'vocabulary',
      columns: ['id'],
      where: 'LOWER(word) = LOWER(?)',
      whereArgs: [entry.word],
    );
    if (exists.isNotEmpty) return -1;
    return db.insert('vocabulary', entry.toMap());
  }

  static Future<List<VocabEntry>> getAllWords() async {
    final db = await _database;
    final rows = await db.query('vocabulary', orderBy: 'added_at DESC');
    return rows.map(VocabEntry.fromMap).toList();
  }

  static Future<Set<String>> getVocabWordSet() async {
    final db = await _database;
    final rows = await db.query('vocabulary', columns: ['word']);
    return rows.map((r) => (r['word'] as String).toLowerCase()).toSet();
  }

  static Future<Map<String, String>> getVocabWordDefMap() async {
    final db = await _database;
    final rows = await db.query('vocabulary', columns: ['word', 'definition']);
    return {
      for (final r in rows)
        (r['word'] as String).toLowerCase(): (r['definition'] as String?) ?? '',
    };
  }

  static Future<void> deleteWord(int id) async {
    final db = await _database;
    await db.delete('vocabulary', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteWordByName(String word) async {
    final db = await _database;
    await db.delete('vocabulary',
        where: 'LOWER(word) = LOWER(?)', whereArgs: [word.toLowerCase()]);
  }

  static Future<void> clearAllWords() async {
    final db = await _database;
    await db.delete('vocabulary');
  }

  // ── Dictionary cache ──────────────────────────────────────────────────────

  static Future<String?> getCached(String word) async {
    final db = await _database;
    final rows = await db.query('dict_cache',
        where: 'word = ?', whereArgs: [word.toLowerCase()]);
    return rows.isNotEmpty ? rows.first['json_data'] as String : null;
  }

  static Future<String?> getChineseCached(String word) async {
    final db = await _database;
    final rows = await db.query('dict_cache',
        columns: ['chinese'],
        where: 'word = ?',
        whereArgs: [word.toLowerCase()]);
    if (rows.isEmpty) return null;
    final v = rows.first['chinese'] as String?;
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<void> cacheDefinition(String word, String json,
      {String chinese = ''}) async {
    final db = await _database;
    await db.insert(
      'dict_cache',
      {'word': word.toLowerCase(), 'json_data': json, 'chinese': chinese},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateChineseCache(String word, String chinese) async {
    final db = await _database;
    await db.update('dict_cache', {'chinese': chinese},
        where: 'word = ?', whereArgs: [word.toLowerCase()]);
  }

  static Future<List<String>?> getDefCnCached(String word) async {
    final db = await _database;
    final rows = await db.query('dict_cache',
        columns: ['def_cn_json'],
        where: 'word = ?',
        whereArgs: [word.toLowerCase()]);
    if (rows.isEmpty) return null;
    final v = rows.first['def_cn_json'] as String?;
    if (v == null || v.isEmpty) return null;
    try {
      return (jsonDecode(v) as List).cast<String>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDefCnCache(String word, List<String> translations) async {
    final db = await _database;
    await db.update(
      'dict_cache',
      {'def_cn_json': jsonEncode(translations)},
      where: 'word = ?',
      whereArgs: [word.toLowerCase()],
    );
  }

  // ── Books ─────────────────────────────────────────────────────────────────

  static Future<Book?> getBookByPath(String filePath) async {
    final db = await _database;
    final rows = await db.query('books',
        where: 'file_path = ?', whereArgs: [filePath]);
    return rows.isNotEmpty ? Book.fromMap(rows.first) : null;
  }

  static Future<Book> upsertBook(Book book) async {
    final db = await _database;
    final existing = await getBookByPath(book.filePath);
    if (existing != null) return existing;
    final id = await db.insert('books', book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return book.copyWith(id: id);
  }

  static Future<List<Book>> getAllBooks() async {
    final db = await _database;
    final rows = await db.query('books', orderBy: 'added_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  static Future<void> updateBookProgress(
      int bookId, int lastPage, int totalPages) async {
    final db = await _database;
    await db.update('books',
        {'last_page': lastPage, 'total_pages': totalPages},
        where: 'id = ?', whereArgs: [bookId]);
  }

  static Future<void> deleteBook(int id) async {
    final db = await _database;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  // ── Custom Dictionaries ───────────────────────────────────────────────────

  static Future<int> addDictSource(DictSource source) async {
    final db = await _database;
    return db.insert('custom_dicts', source.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<DictSource>> getAllDictSources() async {
    final db = await _database;
    final rows = await db.query('custom_dicts', orderBy: 'sort_order ASC, added_at ASC');
    return rows.map(DictSource.fromMap).toList();
  }

  static Future<void> updateDictOrder(List<int> orderedIds) async {
    final db = await _database;
    await db.transaction((t) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await t.update('custom_dicts', {'sort_order': i},
            where: 'id = ?', whereArgs: [orderedIds[i]]);
      }
    });
  }

  static Future<void> updateDictEnabled(int id, bool enabled) async {
    final db = await _database;
    await db.update('custom_dicts', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteDictSource(int id) async {
    final db = await _database;
    await db.delete('custom_dicts', where: 'id = ?', whereArgs: [id]);
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  static Future<void> addBookmark(Bookmark b) async {
    final db = await _database;
    // Avoid duplicate bookmark on same page
    await db.delete('bookmarks',
        where: 'book_id = ? AND page = ?', whereArgs: [b.bookId, b.page]);
    await db.insert('bookmarks', b.toMap());
  }

  static Future<List<Bookmark>> getBookmarks(int bookId) async {
    final db = await _database;
    final rows = await db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'page ASC');
    return rows.map(Bookmark.fromMap).toList();
  }

  static Future<void> deleteBookmark(int id) async {
    final db = await _database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // ── Reader notes ──────────────────────────────────────────────────────────

  static Future<void> addReaderNote(ReaderNote note) async {
    final db = await _database;
    await db.insert('reader_notes', note.toMap());
  }

  static Future<List<ReaderNote>> getReaderNotes(int bookId) async {
    final db = await _database;
    final rows = await db.query('reader_notes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'page ASC');
    return rows.map(ReaderNote.fromMap).toList();
  }

  static Future<void> deleteReaderNote(int id) async {
    final db = await _database;
    await db.delete('reader_notes', where: 'id = ?', whereArgs: [id]);
  }
}
