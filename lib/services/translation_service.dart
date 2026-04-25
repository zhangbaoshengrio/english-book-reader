import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class TranslationEngine {
  final String id;
  final String name;
  final bool isBuiltin;

  const TranslationEngine({
    required this.id,
    required this.name,
    this.isBuiltin = false,
  });
}

class TranslationService {
  static const List<TranslationEngine> builtinEngines = [
    TranslationEngine(id: 'google',   name: 'Google',   isBuiltin: true),
    TranslationEngine(id: 'mymemory', name: 'MyMemory', isBuiltin: true),
  ];

  /// Returns all engines: builtins + custom (if configured).
  static Future<List<TranslationEngine>> getAllEngines() async {
    final custom = await _getCustomEngine();
    return [...builtinEngines, ?custom];
  }

  static Future<TranslationEngine?> _getCustomEngine() async {
    final name = await SettingsService.getCustomTranslationName();
    final url  = await SettingsService.getCustomTranslationUrl();
    if (name.isEmpty || url.isEmpty) return null;
    return TranslationEngine(id: 'custom', name: name);
  }

  /// Translate [text] (English → Chinese) using the given engine.
  static Future<String> translate(String text, String engineId) async {
    switch (engineId) {
      case 'google':   return _google(text);
      case 'mymemory': return _myMemory(text);
      case 'custom':   return _custom(text);
      default:         return _google(text);
    }
  }

  // ── Google Translate (unofficial gtx client) ─────────────────────────────

  static Future<String> _google(String text) async {
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

  // ── MyMemory (free, 1000 chars/day without key) ──────────────────────────

  static Future<String> _myMemory(String text) async {
    try {
      final uri = Uri.parse(
          'https://api.mymemory.translated.net/get'
          '?q=${Uri.encodeComponent(text)}&langpair=en|zh');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final translated = data['responseData']?['translatedText'] as String?;
        return translated ?? '';
      }
    } catch (_) {}
    return '';
  }

  // ── Custom engine ────────────────────────────────────────────────────────

  static Future<String> _custom(String text) async {
    try {
      final urlTemplate = await SettingsService.getCustomTranslationUrl();
      final jsonPath    = await SettingsService.getCustomTranslationJsonPath();
      if (urlTemplate.isEmpty) return '';

      final url = urlTemplate.replaceAll('{text}', Uri.encodeComponent(text));
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        if (jsonPath.isEmpty) return resp.body.trim();
        final data = jsonDecode(resp.body);
        return _extractJsonPath(data, jsonPath) ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// Simple dot-notation JSON path extractor (e.g. "responseData.translatedText").
  static String? _extractJsonPath(dynamic data, String path) {
    dynamic current = data;
    for (final part in path.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current?.toString();
  }
}
