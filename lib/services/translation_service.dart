import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Engine type constants ─────────────────────────────────────────────────────

class EngineType {
  static const builtinFree = 'builtinFree'; // free unofficial endpoint
  static const officialApi = 'officialApi'; // official API with credentials
  static const customUrl   = 'customUrl';   // user-defined URL template
}

// ── Credential field descriptor ───────────────────────────────────────────────

class CredentialField {
  final String key;
  final String label;
  final String hint;

  const CredentialField({
    required this.key,
    required this.label,
    required this.hint,
  });
}

// ── Engine model ──────────────────────────────────────────────────────────────

class TranslationEngine {
  final String id;
  final String name;
  final String type; // EngineType constant
  final bool enabled;
  final String urlTemplate; // customUrl only
  final String jsonPath;    // customUrl only
  final Map<String, String> credentials; // officialApi only

  bool get isBuiltin =>
      type == EngineType.builtinFree || type == EngineType.officialApi;

  const TranslationEngine({
    required this.id,
    required this.name,
    this.type = EngineType.customUrl,
    this.enabled = true,
    this.urlTemplate = '',
    this.jsonPath = '',
    this.credentials = const {},
  });

  TranslationEngine copyWith({
    String? id,
    String? name,
    String? type,
    bool? enabled,
    String? urlTemplate,
    String? jsonPath,
    Map<String, String>? credentials,
  }) =>
      TranslationEngine(
        id:          id          ?? this.id,
        name:        name        ?? this.name,
        type:        type        ?? this.type,
        enabled:     enabled     ?? this.enabled,
        urlTemplate: urlTemplate ?? this.urlTemplate,
        jsonPath:    jsonPath    ?? this.jsonPath,
        credentials: credentials ?? this.credentials,
      );

  Map<String, dynamic> toJson() => {
        'id':          id,
        'name':        name,
        'type':        type,
        'enabled':     enabled,
        'urlTemplate': urlTemplate,
        'jsonPath':    jsonPath,
        'credentials': credentials,
      };

  factory TranslationEngine.fromJson(Map<String, dynamic> j) {
    // Migrate legacy isBuiltin bool → type string
    String t = j['type'] as String? ?? '';
    if (t.isEmpty) {
      t = (j['isBuiltin'] as bool? ?? false)
          ? EngineType.builtinFree
          : EngineType.customUrl;
    }
    final rawCreds = j['credentials'];
    final creds = <String, String>{};
    if (rawCreds is Map) {
      rawCreds.forEach((k, v) {
        if (k is String && v is String) creds[k] = v;
      });
    }
    return TranslationEngine(
      id:          j['id']          as String? ?? '',
      name:        j['name']        as String? ?? '',
      type:        t,
      enabled:     j['enabled']     as bool?   ?? true,
      urlTemplate: j['urlTemplate'] as String? ?? '',
      jsonPath:    j['jsonPath']    as String? ?? '',
      credentials: creds,
    );
  }

  // ── Default engine list ────────────────────────────────────────────────────

  static const List<TranslationEngine> defaults = [
    // Built-in free (unofficial endpoints, no credentials required)
    TranslationEngine(id: 'google',    name: '谷歌',    type: EngineType.builtinFree, enabled: true),
    TranslationEngine(id: 'microsoft', name: '微软',    type: EngineType.builtinFree, enabled: false),
    TranslationEngine(id: 'youdao',   name: '网易有道', type: EngineType.builtinFree, enabled: false),
    TranslationEngine(id: 'baidu',    name: '百度',     type: EngineType.builtinFree, enabled: false),
    TranslationEngine(id: 'sogou',    name: '搜狗',     type: EngineType.builtinFree, enabled: false),
    TranslationEngine(id: 'deepl',    name: 'DeepL',   type: EngineType.builtinFree, enabled: false),
    // Official API engines (need credentials, disabled by default)
    TranslationEngine(id: 'baidu_api',   name: '百度 API',   type: EngineType.officialApi, enabled: false),
    TranslationEngine(id: 'youdao_api',  name: '有道云 API',  type: EngineType.officialApi, enabled: false),
    TranslationEngine(id: 'tencent_api', name: '腾讯云 API',  type: EngineType.officialApi, enabled: false),
    TranslationEngine(id: 'sogou_api',   name: '搜狗 API',   type: EngineType.officialApi, enabled: false),
    TranslationEngine(id: 'deepl_api',   name: 'DeepL API', type: EngineType.officialApi, enabled: false),
  ];

  // ── Credential field definitions per official API engine ──────────────────

  static const Map<String, List<CredentialField>> credentialFields = {
    'baidu_api': [
      CredentialField(key: 'appId',     label: 'App ID', hint: '百度翻译开放平台 APP ID'),
      CredentialField(key: 'appSecret', label: '密钥',   hint: '百度翻译开放平台密钥'),
    ],
    'youdao_api': [
      CredentialField(key: 'appKey',    label: 'App Key',    hint: '有道智云 App Key'),
      CredentialField(key: 'appSecret', label: 'App Secret', hint: '有道智云 App Secret'),
    ],
    'tencent_api': [
      CredentialField(key: 'secretId',  label: 'Secret ID',  hint: '腾讯云 Secret ID'),
      CredentialField(key: 'secretKey', label: 'Secret Key', hint: '腾讯云 Secret Key'),
    ],
    'sogou_api': [
      CredentialField(key: 'pid', label: 'PID',  hint: '搜狗翻译 PID'),
      CredentialField(key: 'key', label: '密钥', hint: '搜狗翻译密钥'),
    ],
    'deepl_api': [
      CredentialField(key: 'authKey', label: 'Auth Key', hint: 'DeepL API Key（免费版以 :fx 结尾）'),
    ],
  };
}

// ── Service ───────────────────────────────────────────────────────────────────

class TranslationService {
  static const _kKey = 'translation_engines_config';

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<List<TranslationEngine>> getEngines() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    if (raw == null) return List.of(TranslationEngine.defaults);
    try {
      final list = jsonDecode(raw) as List;
      final engines = list
          .map((e) => TranslationEngine.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ensure newly-added defaults are present
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
    await p.setString(
        _kKey, jsonEncode(engines.map((e) => e.toJson()).toList()));
  }

  static Future<List<TranslationEngine>> getEnabledEngines() async =>
      (await getEngines()).where((e) => e.enabled).toList();

  /// Save credentials for an official API engine.
  static Future<void> saveCredentials(
      String engineId, Map<String, String> credentials) async {
    final engines = await getEngines();
    final idx = engines.indexWhere((e) => e.id == engineId);
    if (idx >= 0) {
      engines[idx] = engines[idx].copyWith(credentials: credentials);
      await saveEngines(engines);
    }
  }

  /// Add or update a custom URL engine.
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
      id: newId,
      name: name,
      type: EngineType.customUrl,
      enabled: true,
      urlTemplate: urlTemplate,
      jsonPath: jsonPath,
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

  // ── Translation dispatch ───────────────────────────────────────────────────

  static Future<String> translate(String text, String engineId) async {
    if (text.trim().isEmpty) return '';
    try {
      switch (engineId) {
        case 'google':    return await _google(text);
        case 'microsoft': return await _microsoft(text);
        case 'youdao':    return await _youdaoFree(text);
        case 'baidu':     return await _baiduFree(text);
        case 'sogou':     return await _sogouFree(text);
        case 'deepl':     return await _deeplFree(text);
        default:
          final engines = await getEngines();
          final engine = engines.firstWhere((e) => e.id == engineId,
              orElse: () => const TranslationEngine(id: '', name: ''));
          if (engine.id.isEmpty) return '';
          if (engine.type == EngineType.officialApi) {
            return await _callOfficialApi(text, engine);
          }
          if (engine.urlTemplate.isNotEmpty) return await _custom(text, engine);
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  static Future<String> _callOfficialApi(
      String text, TranslationEngine engine) async {
    switch (engine.id) {
      case 'baidu_api':   return _baiduApi(text, engine.credentials);
      case 'youdao_api':  return _youdaoApi(text, engine.credentials);
      case 'tencent_api': return _tencentApi(text, engine.credentials);
      case 'sogou_api':   return _sogouApi(text, engine.credentials);
      case 'deepl_api':   return _deeplApi(text, engine.credentials);
      default:            return '';
    }
  }

  // ── Built-in free engines ──────────────────────────────────────────────────

  /// 谷歌 (gtx unofficial endpoint)
  static Future<String> _google(String text) async {
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
    return '';
  }

  /// 微软 (Edge auth token + Cognitive Services)
  static String? _msToken;

  static Future<String> _microsoft(String text) async {
    _msToken ??= await _fetchMsToken();
    if (_msToken == null) return '';
    try {
      final resp = await http.post(
        Uri.parse('https://api.cognitive.microsofttranslator.com/translate'
            '?api-version=3.0&from=en&to=zh-Hans'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_msToken',
        },
        body: jsonEncode([
          {'Text': text}
        ]),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        return (data[0]?['translations']?[0]?['text'] as String?) ?? '';
      }
      if (resp.statusCode == 401) _msToken = null; // expired
    } catch (_) {
      _msToken = null;
    }
    return '';
  }

  static Future<String?> _fetchMsToken() async {
    try {
      final resp = await http
          .get(Uri.parse('https://edge.microsoft.com/translate/auth'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) return resp.body.trim();
    } catch (_) {}
    return null;
  }

  /// 网易有道 (dict.youdao.com unofficial endpoint)
  static Future<String> _youdaoFree(String text) async {
    try {
      final uri = Uri.parse(
          'https://dict.youdao.com/translate'
          '?doctype=json&type=EN2ZH&i=${Uri.encodeComponent(text)}');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Referer': 'https://dict.youdao.com/',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['translateResult'] as List?;
        if (list != null && list.isNotEmpty) {
          final inner = list.first as List?;
          if (inner != null && inner.isNotEmpty) {
            return (inner.first['tgt'] as String?) ?? '';
          }
        }
      }
    } catch (_) {}
    return '';
  }

  /// 百度 (fanyi.baidu.com unofficial endpoint with token)
  static Future<String> _baiduFree(String text) async {
    try {
      // Step 1: get token from main page
      final pageResp = await http.get(
        Uri.parse('https://fanyi.baidu.com/'),
        headers: {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'},
      ).timeout(const Duration(seconds: 8));
      String token = '';
      final tokenMatch = RegExp(r'token\s*[:=]\s*["\x27]([^"\x27]+)["\x27]').firstMatch(pageResp.body);
      if (tokenMatch != null) token = tokenMatch.group(1) ?? '';
      if (token.isEmpty) return '';

      // Step 2: translate
      final resp = await http.post(
        Uri.parse('https://fanyi.baidu.com/v2transapi?from=en&to=zh'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Referer': 'https://fanyi.baidu.com/',
          'Origin': 'https://fanyi.baidu.com',
        },
        body: 'from=en&to=zh&query=${Uri.encodeComponent(text)}&transtype=translang&simple_means_flag=3&sign=&token=$token&domain=common',
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['trans_result']?['data'] as List?;
        if (list != null && list.isNotEmpty) {
          return (list.first['dst'] as String?) ?? '';
        }
      }
    } catch (_) {}
    return '';
  }

  /// 搜狗 (fanyi.sogou.com unofficial endpoint)
  static Future<String> _sogouFree(String text) async {
    try {
      final uuid = _generateUuid();
      final resp = await http.post(
        Uri.parse('https://fanyi.sogou.com/api/transpc/text/result'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://fanyi.sogou.com/',
          'Origin': 'https://fanyi.sogou.com',
        },
        body: jsonEncode({
          'from': 'en',
          'to': 'zh-CHS',
          'text': text,
          'uuid': uuid,
          'pid': 'sogou-dict-vr',
          'addSugg': '0',
        }),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['data']?['translate']?['dit'] as String?) ?? '';
      }
    } catch (_) {}
    return '';
  }

  static String _generateUuid() {
    final rand = Random();
    String r(int n) => rand.nextInt(n).toRadixString(16).padLeft(4, '0');
    return '${r(65536)}${r(65536)}-${r(65536)}-4${r(4096).substring(1)}-${(rand.nextInt(4) + 8).toRadixString(16)}${r(4096).substring(1)}-${r(65536)}${r(65536)}${r(65536)}';
  }

  /// DeepL (unofficial JSON-RPC endpoint with proper id parity trick)
  static Future<String> _deeplFree(String text) async {
    // DeepL uses id parity check: if "method":"LMT_handle_texts" appears (count+1) times,
    // id must be odd. Using a simple approach: always use an odd id.
    final id = (Random().nextInt(4500000) * 2) + 1000001; // always odd
    try {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'LMT_handle_texts',
        'id': id,
        'params': {
          'texts': [
            {'text': text, 'requestAlternatives': 0}
          ],
          'splitting': 'newlines',
          'lang': {
            'target_lang': 'ZH',
            'source_lang_computed': 'EN',
          },
          'timestamp': _deeplTimestamp(text),
        },
      });
      final resp = await http.post(
        Uri.parse('https://www2.deepl.com/jsonrpc'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'DeepL-iOS/3.7.0 (iPhone; iOS 17.0)',
          'Accept': '*/*',
        },
        body: body,
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final translations = data['result']?['translations'] as List?;
        if (translations != null && translations.isNotEmpty) {
          final beams = translations.first['beams'] as List?;
          if (beams != null && beams.isNotEmpty) {
            final sentences = beams.first['sentences'] as List?;
            if (sentences != null && sentences.isNotEmpty) {
              return (sentences.first['text'] as String?) ?? '';
            }
          }
        }
      }
    } catch (_) {}
    return '';
  }

  static int _deeplTimestamp(String text) {
    // Count 'i' characters to compute timestamp offset (DeepL anti-bot trick)
    final iCount = 'i'.allMatches(text).length + 1;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return ts - (ts % iCount) + iCount;
  }

  // ── Official API engines ───────────────────────────────────────────────────

  /// 百度翻译 API (MD5 signing)
  static Future<String> _baiduApi(
      String text, Map<String, String> creds) async {
    final appId = creds['appId'] ?? '';
    final appSecret = creds['appSecret'] ?? '';
    if (appId.isEmpty || appSecret.isEmpty) return '';
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    final sign =
        md5.convert(utf8.encode('$appId$text$salt$appSecret')).toString();
    final uri = Uri.parse(
        'https://fanyi-api.baidu.com/api/trans/vip/translate'
        '?appid=${Uri.encodeComponent(appId)}'
        '&q=${Uri.encodeComponent(text)}'
        '&from=en&to=zh'
        '&salt=${Uri.encodeComponent(salt)}'
        '&sign=${Uri.encodeComponent(sign)}');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['trans_result'] as List?;
      if (list != null && list.isNotEmpty) {
        return list.map((e) => e['dst'] as String? ?? '').join('\n');
      }
    }
    return '';
  }

  /// 有道云 API (SHA256 v3 signing)
  static Future<String> _youdaoApi(
      String text, Map<String, String> creds) async {
    final appKey = creds['appKey'] ?? '';
    final appSecret = creds['appSecret'] ?? '';
    if (appKey.isEmpty || appSecret.isEmpty) return '';
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    final curtime =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final input = text.length <= 20
        ? text
        : '${text.substring(0, 10)}${text.length}${text.substring(text.length - 10)}';
    final sign =
        sha256.convert(utf8.encode('$appKey$input$salt$curtime$appSecret')).toString();
    final resp = await http.post(
      Uri.parse('https://openapi.youdao.com/api'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'q': text,
        'from': 'en',
        'to': 'zh-CHS',
        'appKey': appKey,
        'salt': salt,
        'sign': sign,
        'signType': 'v3',
        'curtime': curtime,
      },
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['translation'] as List?;
      if (list != null && list.isNotEmpty) return list.first as String? ?? '';
    }
    return '';
  }

  /// 腾讯云 API (TC3-HMAC-SHA256 signing)
  static Future<String> _tencentApi(
      String text, Map<String, String> creds) async {
    final secretId = creds['secretId'] ?? '';
    final secretKey = creds['secretKey'] ?? '';
    if (secretId.isEmpty || secretKey.isEmpty) return '';

    const service = 'tmt';
    const host = 'tmt.tencentcloudapi.com';
    const algorithm = 'TC3-HMAC-SHA256';

    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final date = DateTime.fromMillisecondsSinceEpoch(
            int.parse(timestamp) * 1000,
            isUtc: true)
        .toIso8601String()
        .substring(0, 10);

    final payload = jsonEncode({
      'SourceText': text,
      'Source': 'en',
      'Target': 'zh',
      'ProjectId': 0,
    });

    final hashedPayload = sha256.convert(utf8.encode(payload)).toString();
    const signedHeaders = 'content-type;host';
    final canonicalHeaders =
        'content-type:application/json; charset=utf-8\nhost:$host\n';
    final canonicalRequest =
        'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n$hashedPayload';

    final credentialScope = '$date/$service/tc3_request';
    final hashedCanonical =
        sha256.convert(utf8.encode(canonicalRequest)).toString();
    final stringToSign =
        '$algorithm\n$timestamp\n$credentialScope\n$hashedCanonical';

    List<int> hmacSha256(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final secretDate = hmacSha256(utf8.encode('TC3$secretKey'), date);
    final secretService = hmacSha256(secretDate, service);
    final secretSigning = hmacSha256(secretService, 'tc3_request');
    final signature =
        Hmac(sha256, secretSigning).convert(utf8.encode(stringToSign)).toString();

    final authorization =
        '$algorithm Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    final resp = await http.post(
      Uri.parse('https://$host'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': authorization,
        'Host': host,
        'X-TC-Action': 'TextTranslate',
        'X-TC-Timestamp': timestamp,
        'X-TC-Version': '2018-03-21',
        'X-TC-Region': 'ap-guangzhou',
      },
      body: payload,
    ).timeout(const Duration(seconds: 12));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['Response']?['TargetText'] as String?) ?? '';
    }
    return '';
  }

  /// 搜狗 API (MD5 signing)
  static Future<String> _sogouApi(
      String text, Map<String, String> creds) async {
    final pid = creds['pid'] ?? '';
    final key = creds['key'] ?? '';
    if (pid.isEmpty || key.isEmpty) return '';
    final salt = Random().nextInt(99999).toString();
    final sign =
        md5.convert(utf8.encode('$pid$text$salt$key')).toString();
    final resp = await http.post(
      Uri.parse('https://fanyi.sogou.com/reventondc/api/sogouTranslation'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'from': 'en',
        'to': 'zh-CHS',
        'text': text,
        'pid': pid,
        'salt': salt,
        'sign': sign,
      }),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['translation'] as String?) ?? '';
    }
    return '';
  }

  /// DeepL API (auth key)
  static Future<String> _deeplApi(
      String text, Map<String, String> creds) async {
    final authKey = creds['authKey'] ?? '';
    if (authKey.isEmpty) return '';
    final isFree = authKey.endsWith(':fx');
    final baseUrl = isFree
        ? 'https://api-free.deepl.com/v2/translate'
        : 'https://api.deepl.com/v2/translate';
    final resp = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': 'DeepL-Auth-Key $authKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': [text],
        'source_lang': 'EN',
        'target_lang': 'ZH',
      }),
    ).timeout(const Duration(seconds: 12));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['translations'] as List?;
      if (list != null && list.isNotEmpty) {
        return (list.first['text'] as String?) ?? '';
      }
    }
    return '';
  }

  // ── Custom URL engine ──────────────────────────────────────────────────────

  static Future<String> _custom(String text, TranslationEngine engine) async {
    final url =
        engine.urlTemplate.replaceAll('{text}', Uri.encodeComponent(text));
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    if (resp.statusCode == 200) {
      if (engine.jsonPath.isEmpty) return resp.body.trim();
      final data = jsonDecode(resp.body);
      return _extractPath(data, engine.jsonPath) ?? '';
    }
    return '';
  }

  /// Dot-notation JSON path, e.g. "responseData.translatedText" or "data.0.text"
  static String? _extractPath(dynamic data, String path) {
    dynamic cur = data;
    for (final part in path.split('.')) {
      if (cur is Map) {
        cur = cur[part];
      } else if (cur is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx < cur.length) {
          cur = cur[idx];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return cur?.toString();
  }
}
