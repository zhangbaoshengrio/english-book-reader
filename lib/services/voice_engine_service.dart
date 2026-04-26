import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Engine type constants ──────────────────────────────────────────────────────

class VoiceEngineType {
  static const builtinTts = 'builtinTts'; // system flutter_tts
  static const openaiApi  = 'openaiApi';  // OpenAI TTS API
  static const customUrl  = 'customUrl';  // custom HTTP endpoint returning audio
}

// ── Credential field descriptor ───────────────────────────────────────────────

class VoiceCredentialField {
  final String key;
  final String label;
  final String hint;
  const VoiceCredentialField({required this.key, required this.label, required this.hint});
}

// ── Voice engine model ────────────────────────────────────────────────────────

class VoiceEngine {
  final String id;
  final String name;
  final String type;
  final bool enabled;
  final Map<String, String> credentials;
  final String urlTemplate; // customUrl only
  final String voiceParam;  // selected voice/model param
  final double speed;       // builtin: 0.3-1.5, openai: 0.25-4.0

  bool get isBuiltin => type == VoiceEngineType.builtinTts;

  const VoiceEngine({
    required this.id,
    required this.name,
    this.type = VoiceEngineType.customUrl,
    this.enabled = false,
    this.credentials = const {},
    this.urlTemplate = '',
    this.voiceParam = '',
    this.speed = 1.0,
  });

  VoiceEngine copyWith({
    String? id,
    String? name,
    String? type,
    bool? enabled,
    Map<String, String>? credentials,
    String? urlTemplate,
    String? voiceParam,
    double? speed,
  }) => VoiceEngine(
    id:          id          ?? this.id,
    name:        name        ?? this.name,
    type:        type        ?? this.type,
    enabled:     enabled     ?? this.enabled,
    credentials: credentials ?? this.credentials,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    voiceParam:  voiceParam  ?? this.voiceParam,
    speed:       speed       ?? this.speed,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    'type':        type,
    'enabled':     enabled,
    'credentials': credentials,
    'urlTemplate': urlTemplate,
    'voiceParam':  voiceParam,
    'speed':       speed,
  };

  factory VoiceEngine.fromJson(Map<String, dynamic> j) {
    final rawCreds = j['credentials'];
    final creds = <String, String>{};
    if (rawCreds is Map) {
      rawCreds.forEach((k, v) {
        if (k is String && v is String) creds[k] = v;
      });
    }
    // Default speed by type
    final type = j['type'] as String? ?? VoiceEngineType.customUrl;
    final defaultSpeed = type == VoiceEngineType.builtinTts ? 0.75 : 1.0;
    return VoiceEngine(
      id:          j['id']          as String? ?? '',
      name:        j['name']        as String? ?? '',
      type:        type,
      enabled:     j['enabled']     as bool?   ?? false,
      credentials: creds,
      urlTemplate: j['urlTemplate'] as String? ?? '',
      voiceParam:  j['voiceParam']  as String? ?? '',
      speed:       (j['speed'] as num?)?.toDouble() ?? defaultSpeed,
    );
  }

  // ── Default engine list ──────────────────────────────────────────────────

  static const List<VoiceEngine> defaults = [
    VoiceEngine(
      id:      'builtin',
      name:    '系统内置',
      type:    VoiceEngineType.builtinTts,
      enabled: true,
      speed:   0.75,
    ),
    VoiceEngine(
      id:         'openai_tts',
      name:       'ChatGPT 语音',
      type:       VoiceEngineType.openaiApi,
      enabled:    false,
      voiceParam: 'alloy',
      speed:      1.0,
    ),
  ];

  // ── Credential field definitions ──────────────────────────────────────────

  static const Map<String, List<VoiceCredentialField>> credentialFields = {
    'openai_tts': [
      VoiceCredentialField(key: 'apiKey',  label: 'API Key', hint: 'sk-...'),
      VoiceCredentialField(key: 'model',   label: '模型',    hint: 'tts-1'),
      VoiceCredentialField(key: 'baseUrl', label: '接口',    hint: 'https://api.openai.com/v1/audio/speech'),
    ],
  };

  // OpenAI TTS preset models
  static const List<String> openaiTtsModels = ['tts-1', 'tts-1-hd'];

  // OpenAI available voices
  static const List<String> openaiVoices = [
    'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer',
  ];
}

// ── Service ───────────────────────────────────────────────────────────────────

class VoiceEngineService {
  static const _kKey            = 'voice_engines_config';
  static const _kActiveKey      = 'active_voice_engine';
  static const _kAutoSpeakKey   = 'voice_auto_speak';
  static const _kAiEngineKey    = 'ai_voice_engine_id';
  static const _kAiAutoSpeakKey = 'ai_voice_auto_speak';

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<List<VoiceEngine>> getEngines() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    if (raw == null) return List.of(VoiceEngine.defaults);
    try {
      final list = jsonDecode(raw) as List;
      final engines = list
          .map((e) => VoiceEngine.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final def in VoiceEngine.defaults) {
        if (!engines.any((e) => e.id == def.id)) engines.add(def);
      }
      return engines;
    } catch (_) {
      return List.of(VoiceEngine.defaults);
    }
  }

  static Future<void> saveEngines(List<VoiceEngine> engines) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, jsonEncode(engines.map((e) => e.toJson()).toList()));
  }

  static Future<String> getActiveEngineId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kActiveKey) ?? 'builtin';
  }

  static Future<void> setActiveEngineId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActiveKey, id);
  }

  static Future<bool> getAutoSpeak() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoSpeakKey) ?? false;
  }

  static Future<void> setAutoSpeak(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoSpeakKey, v);
  }

  static Future<String> getAiEngineId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAiEngineKey) ?? 'builtin';
  }

  static Future<void> setAiEngineId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAiEngineKey, id);
  }

  static Future<bool> getAiAutoSpeak() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAiAutoSpeakKey) ?? false;
  }

  static Future<void> setAiAutoSpeak(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAiAutoSpeakKey, v);
  }

  static Future<VoiceEngine?> getAiEngine() async {
    final id = await getAiEngineId();
    final engines = await getEngines();
    try {
      return engines.firstWhere((e) => e.id == id);
    } catch (_) {
      return engines.isNotEmpty ? engines.first : null;
    }
  }

  static Future<void> saveEngineSpeed(String engineId, double speed) async {
    final engines = await getEngines();
    final idx = engines.indexWhere((e) => e.id == engineId);
    if (idx >= 0) {
      engines[idx] = engines[idx].copyWith(speed: speed);
      await saveEngines(engines);
    }
  }

  static Future<VoiceEngine?> getActiveEngine() async {
    final id = await getActiveEngineId();
    final engines = await getEngines();
    try {
      return engines.firstWhere((e) => e.id == id);
    } catch (_) {
      return engines.isNotEmpty ? engines.first : null;
    }
  }

  static Future<void> saveCredentials(
      String engineId, Map<String, String> credentials) async {
    final engines = await getEngines();
    final idx = engines.indexWhere((e) => e.id == engineId);
    if (idx >= 0) {
      engines[idx] = engines[idx].copyWith(credentials: credentials);
      await saveEngines(engines);
    }
  }

  static Future<void> saveCustomEngine({
    String? id,
    required String name,
    required String urlTemplate,
    String voiceParam = '',
  }) async {
    final engines = await getEngines();
    final newId = id ?? 'custom_voice_${DateTime.now().millisecondsSinceEpoch}';
    final idx = engines.indexWhere((e) => e.id == newId);
    final engine = VoiceEngine(
      id:          newId,
      name:        name,
      type:        VoiceEngineType.customUrl,
      enabled:     true,
      urlTemplate: urlTemplate,
      voiceParam:  voiceParam,
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

  // ── Speak dispatch ────────────────────────────────────────────────────────

  /// Returns audio bytes, or null if engine is builtin (caller uses flutter_tts).
  static Future<List<int>?> fetchAudio(String text, VoiceEngine engine) async {
    switch (engine.type) {
      case VoiceEngineType.builtinTts:
        return null; // caller handles via flutter_tts
      case VoiceEngineType.openaiApi:
        return _openaiTts(text, engine);
      case VoiceEngineType.customUrl:
        return _customTts(text, engine);
      default:
        return null;
    }
  }

  /// Play audio bytes by writing to a temp file and using flutter_tts playback.
  /// Returns the temp file path (caller is responsible for deletion if needed).
  static Future<String?> saveTempAudio(List<int> bytes, String ext) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  // ── OpenAI TTS ────────────────────────────────────────────────────────────

  static Future<List<int>?> _openaiTts(String text, VoiceEngine engine) async {
    final apiKey = engine.credentials['apiKey'] ?? '';
    if (apiKey.isEmpty) return null;
    final model = engine.credentials['model']?.isNotEmpty == true
        ? engine.credentials['model']!
        : 'tts-1';
    final voice = engine.voiceParam.isNotEmpty ? engine.voiceParam : 'alloy';
    final baseUrl = engine.credentials['baseUrl']?.isNotEmpty == true
        ? engine.credentials['baseUrl']!
        : 'https://api.openai.com/v1/audio/speech';
    try {
      final resp = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': text,
          'voice': voice,
          'response_format': 'mp3',
          'speed': engine.speed.clamp(0.25, 4.0),
        }),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── Custom URL TTS ────────────────────────────────────────────────────────

  static Future<List<int>?> _customTts(String text, VoiceEngine engine) async {
    if (engine.urlTemplate.isEmpty) return null;
    try {
      final url = engine.urlTemplate
          .replaceAll('{text}', Uri.encodeComponent(text))
          .replaceAll('{voice}', Uri.encodeComponent(engine.voiceParam));
      final resp = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }
}
