import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;

class BookParser {
  static const int perPage = 22;

  static Future<List<String>> parse(String path) async {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'txt')  return _parseTxt(path);
    if (ext == 'epub') return _parseEpub(path);
    throw UnsupportedError('Unsupported format: .$ext');
  }

  // ── TXT ──────────────────────────────────────────────────────────────────
  static Future<List<String>> _parseTxt(String path) async {
    final raw    = await File(path).readAsString();
    final chunks = raw.split(RegExp(r'\n\s*\n'));
    final result = <String>[];

    for (final chunk in chunks) {
      var p = chunk
          .replaceAll('\r', '')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join(' ');
      if (p.isEmpty) continue;

      if (p.length > 1500) {
        final sentences = p.split(RegExp(r'(?<=[.!?])\s+'));
        var buf = '';
        for (final s in sentences) {
          if (buf.length + s.length > 800 && buf.isNotEmpty) {
            result.add(buf.trim());
            buf = s;
          } else {
            buf += (buf.isEmpty ? '' : ' ') + s;
          }
        }
        if (buf.isNotEmpty) result.add(buf.trim());
      } else {
        result.add(p);
      }
    }
    return result;
  }

  // ── EPUB (manual ZIP parsing — no conflicting packages needed) ────────────
  static Future<List<String>> _parseEpub(String path) async {
    final bytes   = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Find OPF path from container.xml
    final containerEntry = _findEntry(archive, 'META-INF/container.xml');
    if (containerEntry == null) throw Exception('Invalid EPUB: missing container.xml');

    final containerXml = utf8.decode(containerEntry.content as List<int>, allowMalformed: true);
    final opfPathMatch  = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
    if (opfPathMatch == null) throw Exception('Invalid EPUB: cannot find OPF path');
    final opfPath = opfPathMatch.group(1)!;
    final opfDir  = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';

    // 2. Parse OPF for manifest + spine
    final opfEntry = _findEntry(archive, opfPath);
    if (opfEntry == null) throw Exception('Invalid EPUB: OPF file missing');
    final opfXml = utf8.decode(opfEntry.content as List<int>, allowMalformed: true);

    final idToHref = <String, String>{};
    for (final m in RegExp(r'<item\s[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"', dotAll: true)
        .allMatches(opfXml)) {
      idToHref[m.group(1)!] = m.group(2)!;
    }

    final spineIds = RegExp(r'<itemref\s[^>]*\bidref="([^"]+)"')
        .allMatches(opfXml)
        .map((m) => m.group(1)!)
        .toList();

    // 3. Extract text in spine order
    final result = <String>[];
    for (final id in spineIds) {
      final href = idToHref[id];
      if (href == null) continue;
      // href may contain fragment (#...), strip it
      final cleanHref = href.split('#').first;
      final fullPath  = opfDir + cleanHref;
      final entry     = _findEntry(archive, fullPath);
      if (entry == null) continue;

      final html = utf8.decode(entry.content as List<int>, allowMalformed: true);
      _extractText(html, result);
    }

    // Fallback: grab all HTML items if spine yielded nothing
    if (result.isEmpty) {
      for (final entry in archive) {
        if (entry.name.endsWith('.html') || entry.name.endsWith('.xhtml') ||
            entry.name.endsWith('.htm')) {
          _extractText(
              utf8.decode(entry.content as List<int>, allowMalformed: true),
              result);
        }
      }
    }
    return result;
  }

  static ArchiveFile? _findEntry(Archive archive, String path) {
    try {
      return archive.findFile(path);
    } catch (_) {
      // Some archives use different path separators
      final alt = path.replaceAll('/', '\\');
      try { return archive.findFile(alt); } catch (_) { return null; }
    }
  }

  static void _extractText(String html, List<String> result) {
    final doc = html_parser.parse(html);
    for (final tag in doc.querySelectorAll('script,style,nav,head')) {
      tag.remove();
    }
    for (final tag in doc.querySelectorAll('p,h1,h2,h3,h4,h5')) {
      final t = tag.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.length > 20) result.add(t);
    }
  }

  // ── Pagination helpers ────────────────────────────────────────────────────
  static int pageCount(int total) =>
      ((total + perPage - 1) ~/ perPage).clamp(1, 999999);

  static List<String> getPage(List<String> paragraphs, int page) {
    final start = page * perPage;
    final end   = (start + perPage).clamp(0, paragraphs.length);
    return paragraphs.sublist(start, end);
  }

  /// Extract the sentence containing [phrase] from [paraText].
  /// Works for single words and multi-word phrases alike.
  static String extractSentence(String paraText, String phrase) {
    final pos = paraText.toLowerCase().indexOf(phrase.toLowerCase());
    if (pos < 0) return paraText.substring(0, paraText.length.clamp(0, 200));

    var start = pos;
    var end   = pos + phrase.length;

    while (start > 0 && !'.!?'.contains(paraText[start - 1])) { start--; }
    while (start < pos && paraText[start].trim().isEmpty) { start++; }
    while (end < paraText.length && !'.!?'.contains(paraText[end])) { end++; }
    if (end < paraText.length) end++;

    var s = paraText.substring(start, end).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.length > 300) {
      final wi = s.toLowerCase().indexOf(phrase.toLowerCase());
      if (wi >= 0) {
        final a = (wi - 110).clamp(0, s.length);
        final b = (wi + phrase.length + 110).clamp(0, s.length);
        s = (a > 0 ? '…' : '') + s.substring(a, b) + (b < s.length ? '…' : '');
      } else {
        s = '${s.substring(0, 297)}…';
      }
    }
    return s;
  }
}
