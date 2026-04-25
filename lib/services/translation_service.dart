import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslationEngine {
  final String id;
  final String name;
  final bool isBuiltin;
  final bool enabled;
  // Custom engines only
  final String urlTemplate;
  final String jsonPath;

  const TranslationEngine({
    required this.id,
    required this.name,
    this.isBuiltin = false,
    this.enabled = true,
    this.urlTemplate = '',
    this.jsonPath = '',
  });

  TranslationEngine copyWith({
    String? id,
    String? name,
    bool? isBuiltin,
    bool? enabled,
    String? urlTemplate,
    String? jsonPath,
  }) => TranslationEngine(
    id:          id          ?? this.id,
    name:        name        ?? this.name,
    isBuiltin:   isBuiltin   ?? this.isBuiltin,
    enabled:     enabled     ?? this.enabled,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    jsonPath:    jsonPath    ?? this.jsonPath,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    'isBuiltin':   isBuiltin,
    'enabled':     enabled,
    'urlTemplate': urlTemplate,
    'jsonPath':    jsonPath,
  };

  factory TranslationEngine.fromJson(Map<String, dynamic> j) => TranslationEngine(
    id:          j['id']          as String? ?? '',
    name:        j['name']        as String? ?? '',
    isBuiltin:   j['isBuiltin']   as bool?   ?? false,
    enabled:     j['enabled']     as bool?   ?? true,
    urlTemplate: j['urlTemplate'] as String? ?? '',
    jsonPath:    j['jsonPath']    as String? ?? '',
  );

  static const List<TranslationEngine> defaults = [
    TranslationEngine(id: 'google',   name: 'Google',   isBuiltin: true, enabled: true),
    TranslationEngine(id: 'mymemory', name: 'MyMemory', isBuiltin: true, enabled: true),
  ];
}

// ── Persistence ────────────────────────────────────────────────────────────────

class TranslationService {
  static const _kKey = 'translation_engines_config';

  static Future<List<TranslationEngine>> getEngines() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    if (raw == null) return List.of(TranslationEngine.defaults);
    try {
      final list = jsonDecode(raw) as List;
      final engines = list
          .map((e) => TranslationEngine.fromJson(e as Map<String, dynamic>))
          .toList();
      // Merge: ensure builtins always present (in case new builtins were added)
      for (final def in TranslationEngine.defaults) {
        if (!engines.any((e) => e.id == def.id)) {
          engines.add(def);
        }
      }
      return engines;
    } catch (_) {
      return List.of(TranslationEngine.defaults);
    }
  }

  static Future<void> saveEngines(List<TranslationEngine> engines) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, jsonEncode(engines.map((e) => e.toJson()).toList()));
  }

  static Future<List<TranslationEngine>> getEnabledEngines() async {
    final all = await getEngines();
    return all.where((e) => e.enabled).toList();
  }

  /// Add or update a custom engine. If [id] is null, generates a new unique id.
  static Future<void> saveCustomEngine({
    String? id,
    required String name,
    required String urlTemplate,
    required String jsonPath,
  }) async {
    final engines = await getEngines();
    final newId = id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final idx = engines.indexWhere((e) => e.id == newId);
    final engine = TranslationEngine(
      id: newId, name: name, isBuiltin: false,
      enabled: true, urlTemplate: urlTemplate, jsonPath: jsonPath,
    );
    if (idx >= 0) {
      engines[idx] = engine;
    } else {
      engines.add(engine);
    }
    await saveEngines(engines);
  }

  static Future<void> deleteEngine(String id) async {
    final engines = await getEngines();
    engines.removeWhere((e) => e.id == id);
    await saveEngines(engines);
  }

  // ── Translation ─────────────────────────────────────────────────────────────

  static Future<String> translate(String text, String engineId) async {
    if (engineId == 'google')   return _google(text);
    if (engineId == 'mymemory') return _myMemory(text);
    // Custom engine
    final engines = await getEngines();
    final engine = engines.firstWhere((e) => e.id == engineId,
        orElse: () => const TranslationEngine(id: '', name: ''));
    if (engine.urlTemplate.isNotEmpty) return _custom(text, engine);
    return '';
  }

  // ── Google Translate (unofficial gtx client) ──────────────────────────────

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

  // ── MyMemory (free, 1000 chars/day without key) ───────────────────────────

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

  // ── Custom engine ─────────────────────────────────────────────────────────

  static Future<String> _custom(String text, TranslationEngine engine) async {
    try {
      final url = engine.urlTemplate
          .replaceAll('{text}', Uri.encodeComponent(text));
      final resp = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        if (engine.jsonPath.isEmpty) return resp.body.trim();
        final data = jsonDecode(resp.body);
        return _extractPath(data, engine.jsonPath) ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// Dot-notation JSON path, e.g. "responseData.translatedText"
  static String? _extractPath(dynamic data, String path) {
    dynamic cur = data;
    for (final part in path.split('.')) {
      if (cur is Map) { cur = cur[part]; } else { return null; }
    }
    return cur?.toString();
  }
}
