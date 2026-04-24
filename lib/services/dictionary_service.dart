import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../models/definition.dart';
import 'database_service.dart';
import 'mdx_service.dart';

class DictionaryService {
  static Future<WordLookupResult> lookup(String word) async {
    final key = word.toLowerCase().trim();

    // 1. All enabled custom dicts (returns every matching source)
    final dictResults = await _lookupAllCustomDicts(key);

    // Derive Chinese meaning from the first dict result that has CJK chars.
    // Strip HTML first so we never store raw markup as the Chinese meaning.
    String customChinese = '';
    for (final dr in dictResults) {
      final plain = dr.isHtml ? _stripHtml(dr.content) : dr.content;
      if (_hasChinese(plain)) {
        customChinese = plain
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && _hasChinese(l))
            .take(2)
            .join('；');
        break;
      }
    }

    // 2. If MDX/custom dict found results, return immediately — no network needed.
    //    Also attach cached phonetic if available (fast SQLite hit).
    //    Kick off a Google Translate fetch in background so starring has clean CN.
    if (dictResults.isNotEmpty) {
      String phonetic = '';
      final cachedJson    = await DatabaseService.getCached(key);
      final cachedChinese = await DatabaseService.getChineseCached(key);
      if (cachedJson != null) {
        phonetic = _parseJson(cachedJson, word).phonetic;
      }
      // Use cached Google Translate if available; otherwise use dict-derived CN.
      final cn = (cachedChinese != null && cachedChinese.isNotEmpty)
          ? cachedChinese
          : customChinese;
      // Always ensure Google Translate is cached for future starring.
      if (cachedChinese == null || cachedChinese.isEmpty) {
        _fetchAndCacheChinese(key);
      }
      return WordLookupResult(
        word: word,
        phonetic: phonetic,
        found: true,
        chineseMeaning: cn,
        dictResults: dictResults,
      );
    }

    // 3. No custom dict hit — try cache then network (FreeDictionary).
    final cachedJson    = await DatabaseService.getCached(key);
    final cachedChinese = await DatabaseService.getChineseCached(key);
    final chineseMeaning = cachedChinese ?? '';

    if (cachedJson != null) {
      if (chineseMeaning.isEmpty) _fetchAndCacheChinese(key);
      final r = _parseJson(cachedJson, word);
      final defs = await _withChineseText(key, r.definitions);
      return WordLookupResult(
        word: r.word,
        phonetic: r.phonetic,
        chineseMeaning: chineseMeaning,
        definitions: defs,
        dictResults: dictResults,
        found: r.found,
      );
    }

    String fetchedJson    = '';
    String fetchedChinese = '';

    try {
      final resp = await http
          .get(Uri.parse(
              'https://api.dictionaryapi.dev/api/v2/entries/en/$key'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) fetchedJson = resp.body;
    } catch (_) {}

    if (fetchedChinese.isEmpty) {
      fetchedChinese = await _fetchChineseTranslation(key);
    }

    if (fetchedJson.isNotEmpty) {
      await DatabaseService.cacheDefinition(key, fetchedJson,
          chinese: fetchedChinese);
      final r = _parseJson(fetchedJson, word, chinese: fetchedChinese);
      final defs = await _withChineseText(key, r.definitions);
      return WordLookupResult(
        word: r.word,
        phonetic: r.phonetic,
        chineseMeaning: r.chineseMeaning,
        definitions: defs,
        dictResults: dictResults,
        found: r.found,
      );
    }

    // 4. Nothing found
    return WordLookupResult(
      word: word,
      found: fetchedChinese.isNotEmpty,
      chineseMeaning: fetchedChinese,
      dictResults: dictResults,
    );
  }

  /// Translate an arbitrary sentence/text to Chinese.
  static Future<String> translateSentence(String text) async {
    try {
      final uri = Uri.parse(
          'https://translate.googleapis.com/translate_a/single'
          '?client=gtx&sl=en&tl=zh-CN&dt=t&q=${Uri.encodeComponent(text)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        final sb = StringBuffer();
        for (final chunk in (data[0] as List)) {
          final t = chunk[0];
          if (t is String) sb.write(t);
        }
        return sb.toString();
      }
    } catch (_) {}
    return '';
  }

  // ── Custom dicts ──────────────────────────────────────────────────────────

  /// Look up [word] in ALL enabled custom dictionaries.
  /// Tries [word] and common inflected variants so lemma-only dicts still hit.
  static Future<List<DictResult>> _lookupAllCustomDicts(String word) async {
    final sources = await DatabaseService.getAllDictSources();
    final results = <DictResult>[];
    final variants = _wordVariants(word);

    debugPrint('[Dict] sources=${sources.length}');
    for (final src in sources) {
      debugPrint('[Dict] src=${src.name} enabled=${src.enabled} '
          'type=${src.type} exists=${File(src.filePath).existsSync()} '
          'path=${src.filePath}');
      if (!src.enabled || src.isBuiltin || !File(src.filePath).existsSync()) continue;
      String? raw;

      for (final variant in variants) {
        switch (src.type) {
          case 'ecdict':
            raw = await _lookupEcdict(src.filePath, variant);
            break;
          case 'tsv':
            raw = await _lookupTsv(src.filePath, variant);
            break;
          case 'mdx':
            try {
              raw = await MdxService.lookup(src.filePath, variant);
            } catch (_) {
              raw = null;
            }
            break;
        }
        if (raw != null && raw.isNotEmpty) break;
      }

      debugPrint('[Dict] ${src.name} raw=${raw?.length}');
      if (raw != null && raw.isNotEmpty) {
        // MDX returns HTML — render it directly; other types are plain text
        if (src.type == 'mdx') {
          results.add(DictResult(name: src.name, content: raw, isHtml: true));
        } else {
          final cleaned = _stripHtml(raw).trim();
          if (cleaned.isNotEmpty) {
            results.add(DictResult(name: src.name, content: cleaned));
          }
        }
      }
    }
    return results;
  }

  static Future<String?> _lookupEcdict(String dbPath, String word) async {
    try {
      final db = await openDatabase(dbPath, readOnly: true);
      final rows = await db.query('stardict',
          columns: ['translation'],
          where: 'word = ? COLLATE NOCASE',
          whereArgs: [word],
          limit: 1);
      await db.close();
      if (rows.isNotEmpty) {
        final t = (rows.first['translation'] as String?) ?? '';
        return t.isNotEmpty ? t : null;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _lookupTsv(String filePath, String word) async {
    try {
      final lower = word.toLowerCase();
      final lines = await File(filePath).readAsLines();
      for (final line in lines) {
        final sep = line.contains('\t') ? '\t' : ',';
        final idx = line.indexOf(sep);
        if (idx <= 0) continue;
        if (line.substring(0, idx).trim().toLowerCase() == lower) {
          return line.substring(idx + 1).trim();
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Network helpers ───────────────────────────────────────────────────────

  static Future<String> _fetchChineseTranslation(String word) async {
    try {
      final uri = Uri.parse(
          'https://translate.googleapis.com/translate_a/single'
          '?client=gtx&sl=en&tl=zh-CN&dt=t&q=${Uri.encodeComponent(word)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        final translation = data[0][0][0] as String;
        if (translation.toLowerCase() != word.toLowerCase()) return translation;
      }
    } catch (_) {}
    return '';
  }

  /// Attach per-definition Chinese translations (cached or fetched in one batch).
  static Future<List<Definition>> _withChineseText(
      String word, List<Definition> defs) async {
    if (defs.isEmpty) return defs;
    // Try cache first
    final cached = await DatabaseService.getDefCnCached(word);
    if (cached != null && cached.length >= defs.length) {
      return List.generate(defs.length, (i) => defs[i].copyWith(chineseText: cached[i]));
    }
    // Batch translate: numbered list so translator preserves order
    try {
      final numbered = defs
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value.text}')
          .join('\n');
      final raw = await translateSentence(numbered);
      final lines = raw
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^\d+[.)） ]+'), '').trim())
          .toList();
      while (lines.length < defs.length) lines.add('');
      await DatabaseService.saveDefCnCache(word, lines.sublist(0, defs.length));
      return List.generate(
          defs.length, (i) => defs[i].copyWith(chineseText: lines[i]));
    } catch (_) {
      return defs;
    }
  }

  static Future<void> _fetchAndCacheChinese(String word) async {
    final cn = await _fetchChineseTranslation(word);
    if (cn.isNotEmpty) await DatabaseService.updateChineseCache(word, cn);
  }

  // ── Text helpers ──────────────────────────────────────────────────────────

  /// Common English inflection variants so lemma-only dicts can match.
  static List<String> _wordVariants(String word) {
    final w = word.toLowerCase();
    final r = <String>{w};

    if (w.endsWith('ing') && w.length > 5) {
      final b = w.substring(0, w.length - 3);
      r.add(b);
      r.add('${b}e');
      if (b.length > 1 && b[b.length - 1] == b[b.length - 2]) {
        r.add(b.substring(0, b.length - 1)); // running→run
      }
    }
    if (w.endsWith('ed') && w.length > 4) {
      final b = w.substring(0, w.length - 2);
      r.add(b);
      r.add('${b}e');
      if (b.length > 1 && b[b.length - 1] == b[b.length - 2]) {
        r.add(b.substring(0, b.length - 1)); // stopped→stop
      }
    }
    if (w.endsWith('es') && w.length > 4) {
      r.add(w.substring(0, w.length - 2));
      r.add(w.substring(0, w.length - 1));
    } else if (w.endsWith('s') && w.length > 3) {
      r.add(w.substring(0, w.length - 1));
    }
    if (w.endsWith('ly') && w.length > 4) {
      r.add(w.substring(0, w.length - 2));
    }
    if (w.endsWith('er') && w.length > 4) {
      r.add(w.substring(0, w.length - 2));
      r.add(w.substring(0, w.length - 1));
    }
    if (w.endsWith('est') && w.length > 5) {
      r.add(w.substring(0, w.length - 3));
    }
    return r.toList();
  }

  /// Walk DOM nodes and produce structured plain text (preserving paragraph breaks).
  static String _nodeToText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'br') return '\n';
      if (const {'script', 'style', 'head'}.contains(tag)) return '';
      final children = node.nodes.map(_nodeToText).join('');
      const blockTags = {
        'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'tr', 'dt', 'dd', 'blockquote', 'article', 'section'
      };
      if (blockTags.contains(tag)) return '$children\n';
      return children;
    }
    return '';
  }

  static String _stripHtml(String html) {
    try {
      final doc = html_parser.parse(html);
      final root = doc.body ?? doc.documentElement;
      if (root == null) return html;
      final text = _nodeToText(root);
      return text
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .replaceAll(RegExp(r' \n|\n '), '\n')
          .trim();
    } catch (_) {
      return html
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
  }

  static bool _hasChinese(String text) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

  // ── JSON parse ────────────────────────────────────────────────────────────

  static WordLookupResult _parseJson(String jsonStr, String word,
      {String chinese = ''}) {
    try {
      final data = jsonDecode(jsonStr) as List;
      String phonetic = '';
      final defs = <Definition>[];

      for (final entry in data) {
        if (phonetic.isEmpty) {
          phonetic = (entry['phonetic'] as String?) ?? '';
          if (phonetic.isEmpty) {
            for (final p in (entry['phonetics'] as List? ?? [])) {
              final t = (p['text'] as String?) ?? '';
              if (t.isNotEmpty) { phonetic = t; break; }
            }
          }
        }
        for (final meaning in (entry['meanings'] as List? ?? [])) {
          final pos = (meaning['partOfSpeech'] as String?) ?? '';
          for (final d in (meaning['definitions'] as List? ?? []).take(2)) {
            defs.add(Definition(
              partOfSpeech: pos,
              text: (d['definition'] as String?) ?? '',
              example: (d['example'] as String?) ?? '',
            ));
          }
          if (defs.length >= 8) break;
        }
        if (defs.length >= 8) break;
      }
      return WordLookupResult(
          word: word,
          phonetic: phonetic,
          chineseMeaning: chinese,
          definitions: defs,
          found: defs.isNotEmpty);
    } catch (_) {
      return WordLookupResult(word: word, found: false, chineseMeaning: chinese);
    }
  }
}
