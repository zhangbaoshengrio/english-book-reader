import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

class AiEngineScreen extends StatefulWidget {
  const AiEngineScreen({super.key});

  @override
  State<AiEngineScreen> createState() => _AiEngineScreenState();
}

class _AiEngineScreenState extends State<AiEngineScreen> {
  List<AiEngine> _engines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engines = await AiService.getEngines();
    if (mounted) setState(() { _engines = engines; _loading = false; });
  }

  Future<void> _save() async => AiService.saveEngines(_engines);

  void _toggleEnabled(int index, bool value) {
    setState(() => _engines[index] = _engines[index].copyWith(enabled: value));
    _save();
  }

  void _showConfigSheet(AiEngine engine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ConfigSheet(
          engine: engine,
          onSave: (updated) async {
            await AiService.saveEngine(updated);
            await _load();
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.groupedBg,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTheme.primary,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('AI 引擎'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                // Info banner
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: AppTheme.primary.withValues(alpha: 0.8)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI 引擎可在查词时提供智能释义，在翻译时提供句子分析。'
                          '配置 API Key 后启用。',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _engines.length,
                    itemBuilder: (context, index) {
                      return _EngineCard(
                        engine: _engines[index],
                        onToggle: (v) => _toggleEnabled(index, v),
                        onConfigure: () => _showConfigSheet(_engines[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Engine card ────────────────────────────────────────────────────────────────

class _EngineCard extends StatelessWidget {
  final AiEngine engine;
  final void Function(bool) onToggle;
  final VoidCallback onConfigure;

  const _EngineCard({
    required this.engine,
    required this.onToggle,
    required this.onConfigure,
  });

  static const _colors = {
    'chatgpt':  Color(0xFF10A37F),
    'gemini':   Color(0xFF4285F4),
    'deepseek': Color(0xFF1A56E8),
  };

  Color get _color => _colors[engine.id] ?? AppTheme.primary;
  bool get _hasKey => engine.apiKey.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Badge
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  engine.name[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(engine.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _hasKey
                          ? (engine.model.isNotEmpty
                              ? '模型: ${engine.model}'
                              : 'API Key 已配置')
                          : '未配置 API Key',
                      style: TextStyle(
                          fontSize: 11,
                          color: _hasKey
                              ? Colors.green.shade600
                              : AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
              // Configure button
              IconButton(
                icon: const Icon(Icons.settings_rounded, size: 18),
                color: AppTheme.textSecondary,
                tooltip: '配置',
                onPressed: onConfigure,
              ),
              // Enable toggle
              Switch(
                value: engine.enabled,
                activeTrackColor: AppTheme.primary.withValues(alpha: 0.4),
                activeThumbColor: AppTheme.primary,
                onChanged: _hasKey ? onToggle : null,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Config bottom sheet ────────────────────────────────────────────────────────

class _ConfigSheet extends StatefulWidget {
  final AiEngine engine;
  final void Function(AiEngine) onSave;

  const _ConfigSheet({required this.engine, required this.onSave});

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _baseUrlCtrl;
  late String _selectedModel;
  bool _obscureKey = true;
  // Test connection state: null=idle, true=testing, false=done
  bool _testing = false;
  String? _testResult; // null=not tested, '' = success msg, starts with '✗'=fail

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.engine.apiKey);
    _baseUrlCtrl = TextEditingController(text: widget.engine.baseUrl);
    final models = AiEngine.modelOptions[widget.engine.id];
    _selectedModel = widget.engine.model.isNotEmpty
        ? widget.engine.model
        : (models?.first ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _testResult = '✗ 请先填写 API Key');
      return;
    }
    setState(() { _testing = true; _testResult = null; });
    try {
      final tmpEngine = widget.engine.copyWith(
        apiKey: key,
        model: _selectedModel,
        enabled: true,
      );
      await AiService.saveEngine(tmpEngine);
      final result = await AiService.query(
        widget.engine.id,
        'Reply with exactly one word: OK',
      );
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = result.isNotEmpty ? '✓ 连接成功' : '✗ 无响应，请检查 API Key 或网络';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = '✗ 连接失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = AiEngine.modelOptions[widget.engine.id] ?? [];
    const labelStyle = TextStyle(
        fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600);
    const dec = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFDDDDDD))),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFDDDDDD))),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
      filled: true,
      fillColor: Color(0xFFF8F8F8),
    );

    final testSuccess = _testResult != null && !_testResult!.startsWith('✗');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Row(children: [
              Text('配置 ${widget.engine.name}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              _apiKeyHint(widget.engine.id),
              style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 20),

            // API Key field
            const Text('API Key', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscureKey,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              decoration: dec.copyWith(
                hintText: 'sk-...',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: AppTheme.textTertiary,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Model selector
            if (models.isNotEmpty) ...[
              const Text('模型', style: labelStyle),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: DropdownButton<String>(
                  value: models.contains(_selectedModel)
                      ? _selectedModel
                      : models.first,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textPrimary),
                  items: models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedModel = v);
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Base URL field (for relay/proxy endpoints)
            if (widget.engine.id == 'chatgpt') ...[
              const Text('API Base URL（中转地址，留空使用官方）', style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _baseUrlCtrl,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: dec.copyWith(
                  hintText: 'https://api.openai.com/v1/chat/completions',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 14),
            ],

            // Test connection button + result
            Row(children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppTheme.primary))
                    : const Icon(Icons.wifi_tethering_rounded, size: 16),
                label: Text(_testing ? '测试中…' : '测试连接',
                    style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 12),
              if (_testResult != null)
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 13,
                      color: testSuccess ? Colors.green.shade600 : Colors.red.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ]),

            const SizedBox(height: 14),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  var baseUrl = _baseUrlCtrl.text.trim();
                  if (baseUrl.isEmpty) {
                    baseUrl = switch (widget.engine.id) {
                      'chatgpt'  => 'https://api.openai.com/v1/chat/completions',
                      'deepseek' => 'https://api.deepseek.com/chat/completions',
                      _          => '',
                    };
                    if (baseUrl.isNotEmpty) _baseUrlCtrl.text = baseUrl;
                  }
                  final updated = widget.engine.copyWith(
                    apiKey: _keyCtrl.text.trim(),
                    model: _selectedModel,
                    baseUrl: baseUrl,
                    enabled: _keyCtrl.text.trim().isNotEmpty
                        ? widget.engine.enabled
                        : false,
                  );
                  widget.onSave(updated);
                },
                child: const Text('保存',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _apiKeyHint(String id) {
    switch (id) {
      case 'chatgpt':
        return '在 OpenAI 平台申请：platform.openai.com/api-keys';
      case 'gemini':
        return '在 Google AI Studio 申请：aistudio.google.com';
      case 'deepseek':
        return '在 DeepSeek 平台申请：platform.deepseek.com';
      default:
        return '';
    }
  }
}
