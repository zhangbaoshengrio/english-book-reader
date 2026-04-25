import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── AI engine model ───────────────────────────────────────────────────────────

class AiEngine {
  final String id;       // 'chatgpt' | 'gemini' | 'deepseek' | custom_xxx
  final String name;
  final String model;    // e.g. 'gpt-4o-mini', 'gemini-1.5-flash', 'deepseek-chat'
  final String apiKey;
  final bool enabled;
  final String baseUrl;  // for custom OpenAI-compatible endpoints

  bool get isBuiltin =>
      id == 'chatgpt' || id == 'gemini' || id == 'deepseek';

  const AiEngine({
    required this.id,
    required this.name,
    this.model = '',
    this.apiKey = '',
    this.enabled = false,
    this.baseUrl = '',
  });

  AiEngine copyWith({
    String? id,
    String? name,
    String? model,
    String? apiKey,
    bool? enabled,
    String? baseUrl,
  }) =>
      AiEngine(
        id:      id      ?? this.id,
        name:    name    ?? this.name,
        model:   model   ?? this.model,
        apiKey:  apiKey  ?? this.apiKey,
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
      );

  Map<String, dynamic> toJson() => {
        'id':      id,
        'name':    name,
        'model':   model,
        'apiKey':  apiKey,
        'enabled': enabled,
        'baseUrl': baseUrl,
      };

  factory AiEngine.fromJson(Map<String, dynamic> j) => AiEngine(
        id:      j['id']      as String? ?? '',
        name:    j['name']    as String? ?? '',
        model:   j['model']   as String? ?? '',
        apiKey:  j['apiKey']  as String? ?? '',
        enabled: j['enabled'] as bool?   ?? false,
        baseUrl: j['baseUrl'] as String? ?? '',
      );

  // ── Built-in defaults ────────────────────────────────────────────────────

  static const List<AiEngine> defaults = [
    AiEngine(
      id: 'chatgpt',
      name: 'ChatGPT',
      model: 'gpt-4o-mini',
      enabled: false,
    ),
    AiEngine(
      id: 'gemini',
      name: 'Gemini',
      model: 'gemini-2.0-flash',
      enabled: false,
    ),
    AiEngine(
      id: 'deepseek',
      name: 'DeepSeek',
      model: 'deepseek-chat',
      enabled: false,
    ),
  ];

  // ── Model options per engine ─────────────────────────────────────────────

  static const Map<String, List<String>> modelOptions = {
    'chatgpt': [
      'gpt-4o-mini',
      'gpt-4o',
      'gpt-4-turbo',
      'gpt-3.5-turbo',
    ],
    'gemini': [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
    'deepseek': [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
  };
}

// ── Prompts ───────────────────────────────────────────────────────────────────

class AiPrompts {
  /// Word lookup: detailed explanation of the word with context.
  static String wordLookup(String word, String sentence) {
    final context = sentence.trim().isNotEmpty
        ? '\n\n原文语境：「$sentence」'
        : '';
    return '请用中文解释英文单词「$word」。$context\n\n请提供：\n'
        '1. 词性和核心中文释义（简洁）\n'
        '2. 在上下文中的具体含义（如有语境）\n'
        '3. 1-2个典型例句（英文+中文）\n'
        '4. 常用搭配或近义词（如有）\n\n'
        '回答要简洁实用，适合英语阅读时快速参考。';
  }

  /// Sentence analysis: translate + grammar + vocabulary breakdown.
  static String sentenceAnalysis(String sentence) {
    return '请分析以下英文句子：\n\n「$sentence」\n\n请提供：\n'
        '1. **中文翻译**（自然流畅）\n'
        '2. **句子结构**（主干+从句/短语分析，简明）\n'
        '3. **重点词汇**（2-4个难点词/短语，含释义）\n\n'
        '回答简洁，适合英语阅读时快速理解。';
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class AiService {
  static const _kKey = 'ai_engines_config';

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<List<AiEngine>> getEngines() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    if (raw == null) return List.of(AiEngine.defaults);
    try {
      final list = jsonDecode(raw) as List;
      final engines = list
          .map((e) => AiEngine.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ensure newly-added defaults are present
      for (final def in AiEngine.defaults) {
        if (!engines.any((e) => e.id == def.id)) {
          engines.add(def);
        }
      }
      return engines;
    } catch (_) {
      return List.of(AiEngine.defaults);
    }
  }

  static Future<void> saveEngines(List<AiEngine> engines) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kKey, jsonEncode(engines.map((e) => e.toJson()).toList()));
  }

  static Future<List<AiEngine>> getEnabledEngines() async =>
      (await getEngines()).where((e) => e.enabled).toList();

  static Future<void> saveEngine(AiEngine engine) async {
    final engines = await getEngines();
    final idx = engines.indexWhere((e) => e.id == engine.id);
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

  // ── API calls ──────────────────────────────────────────────────────────────

  /// Query the AI with a prompt. Returns the response text or empty string on error.
  static Future<String> query(String engineId, String prompt) async {
    if (prompt.trim().isEmpty) return '';
    try {
      final engines = await getEngines();
      final engine = engines.firstWhere((e) => e.id == engineId,
          orElse: () => const AiEngine(id: '', name: ''));
      if (engine.id.isEmpty || engine.apiKey.isEmpty) return '';

      switch (engine.id) {
        case 'chatgpt':
          return await _callOpenAICompatible(
            prompt: prompt,
            apiKey: engine.apiKey,
            model: engine.model.isNotEmpty ? engine.model : 'gpt-4o-mini',
            baseUrl: 'https://api.openai.com/v1/chat/completions',
          );
        case 'gemini':
          return await _callGemini(
            prompt: prompt,
            apiKey: engine.apiKey,
            model: engine.model.isNotEmpty ? engine.model : 'gemini-2.0-flash',
          );
        case 'deepseek':
          return await _callOpenAICompatible(
            prompt: prompt,
            apiKey: engine.apiKey,
            model: engine.model.isNotEmpty ? engine.model : 'deepseek-chat',
            baseUrl: 'https://api.deepseek.com/chat/completions',
          );
        default:
          // Custom OpenAI-compatible endpoint
          if (engine.baseUrl.isNotEmpty) {
            return await _callOpenAICompatible(
              prompt: prompt,
              apiKey: engine.apiKey,
              model: engine.model,
              baseUrl: engine.baseUrl,
            );
          }
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  /// Convenience: word lookup for the first enabled AI engine.
  static Future<String> lookupWord(String word, String sentence) async {
    final engines = await getEnabledEngines();
    if (engines.isEmpty) return '';
    return query(engines.first.id, AiPrompts.wordLookup(word, sentence));
  }

  /// Convenience: sentence analysis for the first enabled AI engine.
  static Future<String> analyzeSentence(String sentence) async {
    final engines = await getEnabledEngines();
    if (engines.isEmpty) return '';
    return query(engines.first.id, AiPrompts.sentenceAnalysis(sentence));
  }

  // ── OpenAI-compatible API (ChatGPT / DeepSeek / custom) ──────────────────

  static Future<String> _callOpenAICompatible({
    required String prompt,
    required String apiKey,
    required String model,
    required String baseUrl,
  }) async {
    final resp = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 800,
        'temperature': 0.3,
      }),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['choices']?[0]?['message']?['content'] as String?) ?? '';
    }
    return '';
  }

  // ── Gemini API ────────────────────────────────────────────────────────────

  static Future<String> _callGemini({
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': 800,
          'temperature': 0.3,
        },
      }),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates.first['content']?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return (parts.first['text'] as String?) ?? '';
        }
      }
    }
    return '';
  }
}
