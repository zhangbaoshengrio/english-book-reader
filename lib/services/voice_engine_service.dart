import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Engine type constants ──────────────────────────────────────────────────────

class VoiceEngineType {
  static const builtinTts   = 'builtinTts';   // system flutter_tts
  static const openaiApi    = 'openaiApi';    // OpenAI TTS API
  static const microsoftTts = 'microsoftTts'; // Azure Cognitive Services TTS
  static const customUrl    = 'customUrl';    // custom HTTP endpoint returning audio
  static const elevenLabsTts  = 'elevenLabsTts';  // ElevenLabs TTS API
  static const volcengineTts  = 'volcengineTts';  // 火山引擎 TTS API
  static const edgeTts        = 'edgeTts';        // Microsoft Edge TTS (free, WebSocket)
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
  final String style;       // speaking instructions (gpt-4o-mini-tts)

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
    this.style = '',
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
    String? style,
  }) => VoiceEngine(
    id:          id          ?? this.id,
    name:        name        ?? this.name,
    type:        type        ?? this.type,
    enabled:     enabled     ?? this.enabled,
    credentials: credentials ?? this.credentials,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    voiceParam:  voiceParam  ?? this.voiceParam,
    speed:       speed       ?? this.speed,
    style:       style       ?? this.style,
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
    'style':       style,
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
      style:       j['style']       as String? ?? '',
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
    VoiceEngine(
      id:         'microsoft_tts',
      name:       '微软 Azure 语音',
      type:       VoiceEngineType.microsoftTts,
      enabled:    false,
      voiceParam: 'en-US-JennyNeural',
      speed:      1.0,
    ),
    VoiceEngine(
      id:         'elevenlabs_tts',
      name:       'ElevenLabs 语音',
      type:       VoiceEngineType.elevenLabsTts,
      enabled:    false,
      voiceParam: '21m00Tcm4TlvDq8ikWAM', // Rachel
      speed:      1.0,
    ),
    VoiceEngine(
      id:         'volcengine_tts',
      name:       '豆包语音',
      type:       VoiceEngineType.volcengineTts,
      enabled:    false,
      voiceParam: '',
      speed:      1.0,
    ),
    VoiceEngine(
      id:         'edge_tts',
      name:       'Edge TTS（免费）',
      type:       VoiceEngineType.edgeTts,
      enabled:    true,
      voiceParam: 'en-US-AriaNeural',
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
    'microsoft_tts': [
      VoiceCredentialField(key: 'apiKey', label: 'API Key',  hint: 'Azure 订阅密钥'),
      VoiceCredentialField(key: 'region', label: 'Region',   hint: 'eastus / southeastasia 等'),
    ],
    'elevenlabs_tts': [
      VoiceCredentialField(key: 'apiKey', label: 'API Key', hint: 'ElevenLabs API Key'),
    ],
    'volcengine_tts': [
      VoiceCredentialField(key: 'appId',      label: 'App ID',      hint: '控制台 AppID（数字）'),
      VoiceCredentialField(key: 'accessKey',  label: 'Access Key',  hint: '控制台 Access Key'),
      VoiceCredentialField(key: 'resourceId', label: 'Resource ID', hint: 'seed-icl-2.0'),
    ],
  };

  // Edge TTS voices (free, no API key required)
  static const List<Map<String, String>> edgeTtsVoices = [
    // en-US
    {'name': 'Aria (美式女)',        'id': 'en-US-AriaNeural'},
    {'name': 'Jenny (美式女)',       'id': 'en-US-JennyNeural'},
    {'name': 'Guy (美式男)',         'id': 'en-US-GuyNeural'},
    {'name': 'Davis (美式男)',       'id': 'en-US-DavisNeural'},
    {'name': 'Ana (美式女/儿童)',    'id': 'en-US-AnaNeural'},
    {'name': 'Christopher (美式男)', 'id': 'en-US-ChristopherNeural'},
    {'name': 'Eric (美式男)',        'id': 'en-US-EricNeural'},
    {'name': 'Michelle (美式女)',    'id': 'en-US-MichelleNeural'},
    {'name': 'Roger (美式男)',       'id': 'en-US-RogerNeural'},
    {'name': 'Steffan (美式男)',     'id': 'en-US-SteffanNeural'},
    // en-GB
    {'name': 'Sonia (英式女)',       'id': 'en-GB-SoniaNeural'},
    {'name': 'Ryan (英式男)',        'id': 'en-GB-RyanNeural'},
    {'name': 'Libby (英式女)',       'id': 'en-GB-LibbyNeural'},
    {'name': 'Maisie (英式女/儿童)', 'id': 'en-GB-MaisieNeural'},
    // en-AU
    {'name': 'Natasha (澳式女)',     'id': 'en-AU-NatashaNeural'},
    {'name': 'William (澳式男)',     'id': 'en-AU-WilliamNeural'},
    // en-IN
    {'name': 'Neerja (印度女)',      'id': 'en-IN-NeerjaNeural'},
    {'name': 'Prabhat (印度男)',     'id': 'en-IN-PrabhatNeural'},
    // en-CA
    {'name': 'Clara (加拿大女)',     'id': 'en-CA-ClaraNeural'},
    {'name': 'Liam (加拿大男)',      'id': 'en-CA-LiamNeural'},
  ];

  static String edgeTtsVoiceNameFor(String id) {
    final v = edgeTtsVoices.firstWhere(
        (v) => v['id'] == id, orElse: () => {'name': id, 'id': id});
    return v['name']!;
  }

  // Microsoft Azure TTS common English neural voices
  static const List<String> microsoftVoices = [
    'en-US-JennyNeural',
    'en-US-GuyNeural',
    'en-US-AriaNeural',
    'en-US-DavisNeural',
    'en-US-AmberNeural',
    'en-US-AnaNeural',
    'en-US-AshleyNeural',
    'en-US-BrandonNeural',
    'en-US-ChristopherNeural',
    'en-US-CoraNeural',
    'en-US-ElizabethNeural',
    'en-US-EricNeural',
    'en-US-JacobNeural',
    'en-US-JaneNeural',
    'en-US-JasonNeural',
    'en-US-MichelleNeural',
    'en-US-MonicaNeural',
    'en-US-NancyNeural',
    'en-US-RogerNeural',
    'en-US-RyanMultilingualNeural',
    'en-US-SaraNeural',
    'en-US-SteffanNeural',
    'en-US-TonyNeural',
    'en-GB-SoniaNeural',
    'en-GB-RyanNeural',
    'en-AU-NatashaNeural',
    'en-AU-WilliamNeural',
  ];

  // OpenAI TTS preset models
  static const List<String> openaiTtsModels = ['tts-1', 'tts-1-hd', 'gpt-4o-mini-tts'];

  // OpenAI available voices
  static const List<String> openaiVoices = [
    'alloy', 'ash', 'coral', 'echo', 'fable', 'onyx', 'nova', 'sage', 'shimmer',
  ];

  // OpenAI TTS speaking style presets (name → instructions)
  static const List<Map<String, String>> openaiTtsStyles = [
    {'name': '默认',       'instruction': ''},
    {'name': '疯狂科学家', 'instruction': 'Speak like a mad scientist — manic, excitable, and full of wild enthusiasm.'},
    {'name': '海岛',       'instruction': 'Speak with a relaxed, laid-back island vibe — unhurried, warm, and carefree.'},
    {'name': '黑色电影侦探','instruction': 'Speak like a noir film detective — world-weary, cynical, and mysterious.'},
    {'name': '机器人',     'instruction': 'Speak like a robot — flat, mechanical, and monotone with precise enunciation.'},
    {'name': '健身教练',   'instruction': 'Speak like an enthusiastic fitness trainer — motivating, energetic, and pumped up.'},
    {'name': '鉴赏家',     'instruction': 'Speak like a refined connoisseur — sophisticated, measured, and deeply knowledgeable.'},
    {'name': '啦啦队长',   'instruction': 'Speak like a peppy cheerleader — upbeat, spirited, and full of positive energy.'},
    {'name': '老式',       'instruction': 'Speak in an old-fashioned, formal manner — dignified, deliberate, and classic.'},
    {'name': '冷静',       'instruction': 'Speak in a calm, measured tone — steady, composed, and reassuring.'},
    {'name': '美食厨师',   'instruction': 'Speak like a passionate culinary chef — expressive, sensory, and full of flavor.'},
    {'name': '耐心老师',   'instruction': 'Speak like a patient teacher — clear, encouraging, and easy to understand.'},
    {'name': '宁静',       'instruction': 'Speak in a serene, peaceful tone — gentle, soft, and calming.'},
    {'name': '牛仔',       'instruction': 'Speak like a rugged cowboy — drawling, laid-back, with a frontier spirit.'},
  ];

  // ElevenLabs voices (name → voice_id)
  static const List<Map<String, String>> elevenLabsVoices = [
    {'name': 'Rachel',    'id': '21m00Tcm4TlvDq8ikWAM'},
    {'name': 'Clyde',     'id': '2EiwWnXFnvU5JabPnv8n'},
    {'name': 'Domi',      'id': 'AZnzlk1XvdvUeBnXmlld'},
    {'name': 'Dave',      'id': 'CYw3kZ78EXxDvMYHYgAZ'},
    {'name': 'Fin',       'id': 'D38z5RcWu1voky8WS1ja'},
    {'name': 'Bella',     'id': 'EXAVITQu4vr4xnSDxMaL'},
    {'name': 'Antoni',    'id': 'ErXwobaYiN019PkySvjV'},
    {'name': 'Charlie',   'id': 'IKne3meq5aSn9XLyUdCD'},
    {'name': 'George',    'id': 'JBFqnCBsd6RMkjVDRZzb'},
    {'name': 'Emily',     'id': 'LcfcDJNUP1GQjkzn1xUU'},
    {'name': 'Elli',      'id': 'MF3mGyEYCl7XYWbV9V6O'},
    {'name': 'Callum',    'id': 'N2lVS1w4EtoT3dr4eOWO'},
    {'name': 'Harry',     'id': 'SOYHLrjzK2X1ezoPC6cr'},
    {'name': 'Liam',      'id': 'TX3LPaxmHKxFdv7VOQHJ'},
    {'name': 'Dorothy',   'id': 'ThT5KcBeYPX3keUQqHPh'},
    {'name': 'Josh',      'id': 'TxGEqnHWrfWFTfGW9XjX'},
    {'name': 'Arnold',    'id': 'VR6AewLTigWG4xSOukaG'},
    {'name': 'Charlotte', 'id': 'XB0fDUnXU5powFXDhCwa'},
    {'name': 'Matilda',   'id': 'XrExE9yKIg1WjnnlVkGX'},
    {'name': 'James',     'id': 'ZQe5CZNOzWyzPSCn5a3c'},
    {'name': 'Freya',     'id': 'jsCqWAovK2LkecY7zXl4'},
    {'name': 'Gigi',      'id': 'jBpfuIE2acCO8z3wKNLl'},
    {'name': 'Jeremy',    'id': 'bVMeCyTHy58xNoL34h3p'},
    {'name': 'Michael',   'id': 'flq6f7yjXakVcjGjq9Vh'},
    {'name': 'Ethan',     'id': 'g5CIjZEefAph4nQFvHAz'},
    {'name': 'Nicole',    'id': 'piTKgcLEGmPE4e6mEKli'},
    {'name': 'Sam',       'id': 'yoZ06aMxZJJ28mfd3POQ'},
  ];

  static String volcengineVoiceNameFor(String id) {
    if (id.isEmpty) return '未设置';
    return id.length > 16 ? '${id.substring(0, 8)}…' : id;
  }

  static String elevenLabsVoiceNameFor(String id) {
    final v = elevenLabsVoices.firstWhere(
        (v) => v['id'] == id, orElse: () => {'name': id, 'id': id});
    return v['name']!;
  }

  /// Display name for a given instruction string (empty → "默认").
  static String styleNameFor(String instruction) {
    if (instruction.isEmpty) return '默认';
    return openaiTtsStyles
        .firstWhere((s) => s['instruction'] == instruction,
            orElse: () => {'name': '自定义'})['name']!;
  }
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

  static Future<void> saveEngineVoiceStyle(String id,
      {String? voice, String? style}) async {
    final engines = await getEngines();
    final idx = engines.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    engines[idx] = engines[idx].copyWith(
      voiceParam: voice ?? engines[idx].voiceParam,
      style:      style ?? engines[idx].style,
    );
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
      case VoiceEngineType.microsoftTts:
        return _microsoftTts(text, engine);
      case VoiceEngineType.elevenLabsTts:
        return _elevenLabsTts(text, engine);
      case VoiceEngineType.volcengineTts:
        return _volcengineTts(text, engine);
      case VoiceEngineType.edgeTts:
        return _edgeTts(text, engine);
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
          if (engine.style.isNotEmpty) 'instructions': engine.style,
        }),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── Microsoft Azure TTS ───────────────────────────────────────────────────

  static Future<List<int>?> _microsoftTts(String text, VoiceEngine engine) async {
    final apiKey = engine.credentials['apiKey'] ?? '';
    final region = engine.credentials['region'] ?? '';
    if (apiKey.isEmpty || region.isEmpty) return null;
    final voice = engine.voiceParam.isNotEmpty ? engine.voiceParam : 'en-US-JennyNeural';
    // Speed: Azure uses <prosody rate> where 1.0 = normal, expressed as percentage
    final rate = engine.speed == 1.0 ? 'default' : '${((engine.speed - 1.0) * 100).toStringAsFixed(0)}%';
    final ssml = '''<speak version='1.0' xml:lang='en-US'>
  <voice name='$voice'>
    <prosody rate='$rate'>
      ${text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </prosody>
  </voice>
</speak>''';
    try {
      final resp = await http.post(
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/v1'),
        headers: {
          'Ocp-Apim-Subscription-Key': apiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-48khz-192kbitrate-mono-mp3',
          'User-Agent': 'EnglishReader',
        },
        body: ssml,
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── ElevenLabs TTS ───────────────────────────────────────────────────────

  static Future<List<int>?> _elevenLabsTts(String text, VoiceEngine engine) async {
    final apiKey = engine.credentials['apiKey'] ?? '';
    if (apiKey.isEmpty) return null;
    final voiceId = engine.voiceParam.isNotEmpty
        ? engine.voiceParam
        : '21m00Tcm4TlvDq8ikWAM';
    try {
      final resp = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId'),
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_monolingual_v1',
          'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
        }),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── 豆包语音 TTS (V3 HTTP) ────────────────────────────────────────────────

  static Future<List<int>?> _volcengineTts(String text, VoiceEngine engine) async {
    final appId     = engine.credentials['appId']     ?? '';
    final accessKey = engine.credentials['accessKey'] ?? '';
    final speaker   = engine.voiceParam;
    if (appId.isEmpty || accessKey.isEmpty || speaker.isEmpty) return null;
    final resourceId = engine.credentials['resourceId']?.isNotEmpty == true
        ? engine.credentials['resourceId']!
        : 'seed-icl-2.0';
    try {
      final resp = await http.post(
        Uri.parse('https://openspeech.bytedance.com/api/v3/tts/unidirectional'),
        headers: {
          'X-Api-App-Id':    appId,
          'X-Api-Access-Key': accessKey,
          'X-Api-Resource-Id': resourceId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user': {'uid': 'english_reader'},
          'req_params': {
            'text': text,
            'speaker': speaker,
            'audio_params': {
              'format': 'mp3',
              'sample_rate': 24000,
            },
          },
        }),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        // Response is NDJSON: each line is {"code":0,"data":"base64mp3..."}
        // Final line has code 20000000 (end of stream)
        final audio = <int>[];
        for (final line in resp.body.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final chunk = jsonDecode(trimmed) as Map<String, dynamic>;
            final code = chunk['code'] as int? ?? -1;
            if (code == 20000000) break; // end of stream
            if (code == 0) {
              final b64 = chunk['data'] as String?;
              if (b64 != null && b64.isNotEmpty) audio.addAll(base64Decode(b64));
            } else {
              final msg = chunk['message'] ?? chunk['msg'] ?? '合成失败';
              throw Exception('code=$code $msg');
            }
          } catch (e) {
            if (e is Exception) rethrow;
          }
        }
        if (audio.isNotEmpty) return audio;
      } else {
        final body = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
        throw Exception('HTTP ${resp.statusCode}: $body');
      }
    } catch (e) {
      if (e is Exception) rethrow;
    }
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

  // ── Edge TTS (Microsoft Edge WebSocket, free) ─────────────────────────────

  static bool _hasChinese(String text) =>
      text.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

  static Future<List<int>?> _edgeTts(String text, VoiceEngine engine) async {
    // If text contains Chinese characters, use a bilingual voice automatically
    final voice = _hasChinese(text)
        ? 'zh-CN-XiaoxiaoNeural'
        : (engine.voiceParam.isNotEmpty ? engine.voiceParam : 'en-US-AriaNeural');

    final speedOffset = ((engine.speed - 1.0) * 100).round();
    final rateStr = speedOffset >= 0 ? '+$speedOffset%' : '$speedOffset%';

    final requestId = _generateRequestId();
    final now = _edgeTtsTimestamp();

    // Build the path+query manually as a plain string to avoid Uri encoding bugs
    const host = 'speech.platform.bing.com';
    const token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
    final secMsGec = _generateSecMsGec(token);
    const secMsGecVersion = '1-143.0.3650.75';
    final muid = _generateMuid();
    final pathAndQuery =
        '/consumer/speech/synthesize/readaloud/edge/v1'
        '?TrustedClientToken=$token'
        '&ConnectionId=$requestId'
        '&Sec-MS-GEC=$secMsGec'
        '&Sec-MS-GEC-Version=$secMsGecVersion';

    SecureSocket? socket;
    try {
      // Connect via TLS directly — no Uri parsing involved
      socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 10),
      );

      // WebSocket handshake key (base64 of 16 random bytes)
      final keyBytes = List<int>.generate(16, (i) =>
          (requestId.codeUnitAt(i % requestId.length) ^ i) & 0xFF);
      final wsKey = base64Encode(keyBytes);

      // Send HTTP Upgrade request with permessage-deflate extension
      final handshake =
          'GET $pathAndQuery HTTP/1.1\r\n'
          'Host: $host\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Key: $wsKey\r\n'
          'Sec-WebSocket-Version: 13\r\n'
          'Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n'
          'Pragma: no-cache\r\n'
          'Cache-Control: no-cache\r\n'
          'Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold\r\n'
          'Accept-Language: en-US,en;q=0.9\r\n'
          'Cookie: muid=$muid;\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0\r\n'
          '\r\n';
      socket.add(utf8.encode(handshake));

      // Use a single listen over the entire session (header + audio)
      return await _edgeTtsSession(
          socket, requestId, now, voice, rateStr, escapedFor(text));
    } catch (e) {
      throw Exception('Edge TTS 连接失败: $e');
    } finally {
      socket?.destroy();
    }
  }

  static String escapedFor(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // Send a masked WebSocket text frame to the socket
  static void _wsSendText(SecureSocket socket, String msg) {
    final payload = utf8.encode(msg);
    const mask = [0x37, 0xfa, 0x21, 0x3d];
    final masked = List<int>.generate(
        payload.length, (i) => payload[i] ^ mask[i % 4]);
    final frame = <int>[0x81]; // FIN + text opcode
    if (payload.length < 126) {
      frame.add(0x80 | payload.length);
    } else if (payload.length < 65536) {
      frame.add(0x80 | 126);
      frame.add((payload.length >> 8) & 0xFF);
      frame.add(payload.length & 0xFF);
    } else {
      frame.add(0x80 | 127);
      for (int shift = 56; shift >= 0; shift -= 8) {
        frame.add((payload.length >> shift) & 0xFF);
      }
    }
    frame.addAll(mask);
    frame.addAll(masked);
    socket.add(frame);
  }

  /// Single-listen session: HTTP upgrade → send messages → collect audio.
  static Future<List<int>?> _edgeTtsSession(
    SecureSocket socket,
    String requestId,
    String now,
    String voice,
    String rateStr,
    String escapedText,
  ) async {
    final completer = Completer<List<int>?>();
    final buf = <int>[];
    bool handshakeDone = false;
    final audioData = <int>[];

    final timer = Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.completeError(Exception(
            handshakeDone ? 'Edge TTS 超时' : '握手超时'));
      }
    });

    socket.listen(
      (chunk) {
        if (completer.isCompleted) return;
        buf.addAll(chunk);

        if (!handshakeDone) {
          // Looking for end of HTTP headers (\r\n\r\n)
          for (int i = 0; i < buf.length - 3; i++) {
            if (buf[i] == 0x0D && buf[i+1] == 0x0A &&
                buf[i+2] == 0x0D && buf[i+3] == 0x0A) {
              final responseHead = utf8.decode(buf.sublist(0, i), allowMalformed: true);
              if (!responseHead.contains('101')) {
                timer.cancel();
                final short = responseHead.length > 500
                    ? responseHead.substring(0, 500) : responseHead;
                completer.completeError(Exception('握手失败:\n$short'));
                return;
              }
              handshakeDone = true;
              // Keep only bytes after the header
              final remaining = buf.sublist(i + 4);
              buf.clear();
              buf.addAll(remaining);
              break;
            }
          }
          if (!handshakeDone) return;

          // Handshake OK — send speech.config and SSML
          _wsSendText(socket,
            'X-Timestamp:$now\r\n'
            'Content-Type:application/json; charset=utf-8\r\n'
            'Path:speech.config\r\n\r\n'
            '{"context":{"synthesis":{"audio":{"metadataoptions":{'
            '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
            '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}',
          );
          final ssml =
              "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
              "xmlns:mstts='http://www.w3.org/2001/mstts' xml:lang='en-US'>"
              "<voice name='$voice'>"
              "<prosody rate='$rateStr'>$escapedText</prosody>"
              '</voice></speak>';
          _wsSendText(socket,
            'X-RequestId:$requestId\r\n'
            'Content-Type:application/ssml+xml\r\n'
            'X-Timestamp:$now\r\n'
            'Path:ssml\r\n\r\n'
            '$ssml',
          );
        }

        // Parse WebSocket frames
        while (buf.length >= 2) {
          final b0 = buf[0];
          final b1 = buf[1];
          final opcode = b0 & 0x0F;
          final rsv1 = (b0 & 0x40) != 0; // permessage-deflate compressed
          final isMasked = (b1 & 0x80) != 0;
          int payloadLen = b1 & 0x7F;
          int headerLen = 2 + (isMasked ? 4 : 0);
          if (payloadLen == 126) {
            if (buf.length < 4) break;
            payloadLen = (buf[2] << 8) | buf[3];
            headerLen += 2;
          } else if (payloadLen == 127) {
            if (buf.length < 10) break;
            payloadLen = 0;
            for (int i = 2; i < 10; i++) payloadLen = (payloadLen << 8) | buf[i];
            headerLen += 8;
          }
          if (buf.length < headerLen + payloadLen) break;

          List<int> payload = buf.sublist(headerLen, headerLen + payloadLen);
          buf.removeRange(0, headerLen + payloadLen);

          // Decompress if RSV1 bit set (permessage-deflate)
          if (rsv1 && payload.isNotEmpty) {
            // Append 4-byte tail required by deflate spec
            final deflated = [...payload, 0x00, 0x00, 0xFF, 0xFF];
            try {
              payload = ZLibDecoder(raw: true).convert(deflated);
            } catch (_) {
              // If decompression fails, use raw payload
            }
          }

          if (opcode == 0x01) {
            final text = utf8.decode(payload, allowMalformed: true);
            if (text.contains('Path:turn.end')) {
              timer.cancel();
              completer.complete(audioData.isNotEmpty ? audioData : null);
              return;
            }
          } else if (opcode == 0x02) {
            // Binary frame format: 2-byte big-endian uint16 = text header length,
            // then text header bytes, then MP3 audio data
            if (payload.length > 2) {
              final headerLen = (payload[0] << 8) | payload[1];
              final audioStart = 2 + headerLen;
              if (audioStart < payload.length) {
                audioData.addAll(payload.sublist(audioStart));
              }
            }
          } else if (opcode == 0x08) {
            timer.cancel();
            completer.complete(audioData.isNotEmpty ? audioData : null);
            return;
          } else if (opcode == 0x09) {
            // Ping — send pong
            socket.add([0x8A, 0x80, 0x00, 0x00, 0x00, 0x00]);
          }
        }
      },
      onError: (e) {
        timer.cancel();
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(audioData.isNotEmpty ? audioData : null);
        }
      },
    );

    return await completer.future;
  }

  static String _generateRequestId() {
    // uuid4 hex — 32 lowercase hex chars, no dashes
    final r = DateTime.now().microsecondsSinceEpoch;
    final a = r.toRadixString(16).padLeft(16, '0');
    final b = (r ^ 0xdeadbeefcafe).toRadixString(16).padLeft(16, '0');
    return (a + b).substring(0, 32);
  }

  // Generate Sec-MS-GEC token (SHA256 of Windows ticks rounded to 5min + token)
  static String _generateSecMsGec(String trustedToken) {
    const winEpoch = 11644473600; // seconds from 1601-01-01 to 1970-01-01
    final unixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ticks = ((unixSec + winEpoch) ~/ 300) * 300 * 10000000;
    final strToHash = '${ticks.toInt()}$trustedToken';
    final digest = sha256.convert(ascii.encode(strToHash));
    return digest.toString().toUpperCase();
  }

  // Generate random 32-char uppercase hex for Cookie muid
  static String _generateMuid() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final a = t.toRadixString(16).padLeft(16, '0').toUpperCase();
    final b = (t ^ 0xfeedf00dbaad).toRadixString(16).padLeft(16, '0').toUpperCase();
    return (a + b).substring(0, 32);
  }

  static String _edgeTtsTimestamp() {
    final now = DateTime.now().toUtc();
    // Format: Wed, 01 Jan 2025 00:00:00 GMT
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final wd = weekdays[now.weekday - 1];
    final mo = months[now.month - 1];
    final d = now.day.toString().padLeft(2, '0');
    final y = now.year.toString();
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$wd, $d $mo $y $h:$mi:$s GMT';
  }
}
