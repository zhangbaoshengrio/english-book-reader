import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../theme/app_theme.dart';

class TranslationEngineScreen extends StatefulWidget {
  const TranslationEngineScreen({super.key});

  @override
  State<TranslationEngineScreen> createState() =>
      _TranslationEngineScreenState();
}

class _TranslationEngineScreenState extends State<TranslationEngineScreen> {
  List<TranslationEngine> _engines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engines = await TranslationService.getEngines();
    if (mounted) setState(() { _engines = engines; _loading = false; });
  }

  Future<void> _save() async {
    await TranslationService.saveEngines(_engines);
  }

  void _toggleEnabled(int index, bool value) {
    setState(() => _engines[index] = _engines[index].copyWith(enabled: value));
    _save();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _engines.removeAt(oldIndex);
      _engines.insert(newIndex, item);
    });
    _save();
  }

  Future<void> _deleteEngine(TranslationEngine engine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除引擎'),
        content: Text('确认删除「${engine.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _engines.removeWhere((e) => e.id == engine.id));
      await _save();
    }
  }

  void _showAddSheet({TranslationEngine? editing}) {
    final nameCtrl     = TextEditingController(text: editing?.name ?? '');
    final urlCtrl      = TextEditingController(text: editing?.urlTemplate ?? '');
    final jsonPathCtrl = TextEditingController(text: editing?.jsonPath ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddEngineSheet(
          nameCtrl: nameCtrl,
          urlCtrl: urlCtrl,
          jsonPathCtrl: jsonPathCtrl,
          isEditing: editing != null,
          onSave: () async {
            final name = nameCtrl.text.trim();
            final url  = urlCtrl.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            final nav = Navigator.of(ctx);
            await TranslationService.saveCustomEngine(
              id: editing?.id,
              name: name,
              urlTemplate: url,
              jsonPath: jsonPathCtrl.text.trim(),
            );
            await _load();
            if (mounted) nav.pop();
          },
        ),
      ),
    );
  }

  void _showCredentialSheet(TranslationEngine engine) {
    final fields = TranslationEngine.credentialFields[engine.id] ?? [];
    final controllers = {
      for (final f in fields)
        f.key: TextEditingController(text: engine.credentials[f.key] ?? ''),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CredentialSheet(
          engine: engine,
          fields: fields,
          controllers: controllers,
          onSave: () async {
            final creds = {
              for (final f in fields) f.key: controllers[f.key]!.text.trim(),
            };
            final nav = Navigator.of(ctx);
            await TranslationService.saveCredentials(engine.id, creds);
            await _load();
            if (mounted) nav.pop();
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
        title: const Text('翻译引擎'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            color: AppTheme.primary,
            tooltip: '添加自定义引擎',
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: const Text(
                    '长按拖动可调整顺序；官方 API 引擎需点击钥匙图标配置密钥后启用',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _engines.length,
                    onReorder: _onReorder,
                    proxyDecorator: (child, index, animation) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final engine = _engines[index];
                      final isCustom = engine.type == EngineType.customUrl;
                      final isApiEngine = engine.type == EngineType.officialApi;
                      return _EngineRow(
                        key: ValueKey(engine.id),
                        engine: engine,
                        isLast: index == _engines.length - 1,
                        onToggle: (v) => _toggleEnabled(index, v),
                        onConfigure: isApiEngine
                            ? () => _showCredentialSheet(engine)
                            : null,
                        onEdit: isCustom ? () => _showAddSheet(editing: engine) : null,
                        onDelete: isCustom ? () => _deleteEngine(engine) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Engine row ─────────────────────────────────────────────────────────────────

class _EngineRow extends StatelessWidget {
  final TranslationEngine engine;
  final bool isLast;
  final void Function(bool) onToggle;
  final VoidCallback? onConfigure; // officialApi
  final VoidCallback? onEdit;      // customUrl
  final VoidCallback? onDelete;    // customUrl

  const _EngineRow({
    super.key,
    required this.engine,
    required this.isLast,
    required this.onToggle,
    this.onConfigure,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 1),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(children: [
        // Drag handle
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Icon(Icons.drag_handle_rounded,
              size: 20, color: AppTheme.textTertiary),
        ),
        // Engine badge
        _EngineBadge(engine: engine),
        const SizedBox(width: 10),
        // Name + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text(engine.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                _TypeTag(engine.type),
              ]),
              if (engine.type == EngineType.customUrl &&
                  engine.urlTemplate.isNotEmpty)
                Text(
                  engine.urlTemplate.length > 40
                      ? '${engine.urlTemplate.substring(0, 40)}…'
                      : engine.urlTemplate,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (engine.type == EngineType.officialApi)
                Text(
                  _credentialStatus(engine),
                  style: TextStyle(
                      fontSize: 11,
                      color: _hasCredentials(engine)
                          ? Colors.green.shade600
                          : AppTheme.textTertiary),
                ),
            ],
          ),
        ),
        // Configure button (officialApi)
        if (onConfigure != null)
          IconButton(
            icon: const Icon(Icons.key_rounded, size: 18),
            color: AppTheme.textSecondary,
            tooltip: '配置密钥',
            onPressed: onConfigure,
          ),
        // Edit + delete (customUrl)
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18),
            color: AppTheme.textSecondary,
            onPressed: onEdit,
          ),
        if (onDelete != null)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: Colors.red.shade400,
            onPressed: onDelete,
          ),
        // Enable toggle
        Switch(
          value: engine.enabled,
          activeTrackColor: AppTheme.primary.withValues(alpha: 0.4),
          activeThumbColor: AppTheme.primary,
          onChanged: onToggle,
        ),
        const SizedBox(width: 4),
      ]),
    );
  }

  bool _hasCredentials(TranslationEngine engine) {
    final fields = TranslationEngine.credentialFields[engine.id] ?? [];
    return fields.isNotEmpty &&
        fields.every((f) => (engine.credentials[f.key] ?? '').isNotEmpty);
  }

  String _credentialStatus(TranslationEngine engine) {
    return _hasCredentials(engine) ? '已配置' : '未配置（点击钥匙图标配置）';
  }
}

// ── Type tag badge ─────────────────────────────────────────────────────────────

class _TypeTag extends StatelessWidget {
  final String type;
  const _TypeTag(this.type);

  static const _labels = {
    EngineType.builtinFree: '免费',
    EngineType.officialApi: 'API',
    EngineType.customUrl:   '自定义',
  };

  static const _colors = {
    EngineType.builtinFree: Color(0xFF34A853),
    EngineType.officialApi: Color(0xFFFF9800),
    EngineType.customUrl:   AppTheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[type] ?? type;
    final color = _colors[type] ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Engine badge (colored letter) ─────────────────────────────────────────────

class _EngineBadge extends StatelessWidget {
  final TranslationEngine engine;
  const _EngineBadge({required this.engine});

  static const _colors = {
    'google':      Color(0xFF4285F4),
    'microsoft':   Color(0xFF00A4EF),
    'youdao':      Color(0xFFD92B2B),
    'baidu':       Color(0xFF2932E1),
    'sogou':       Color(0xFFFF6600),
    'deepl':       Color(0xFF0F2B46),
    'baidu_api':   Color(0xFF2932E1),
    'youdao_api':  Color(0xFFD92B2B),
    'tencent_api': Color(0xFF1BA784),
    'sogou_api':   Color(0xFFFF6600),
    'deepl_api':   Color(0xFF0F2B46),
  };

  Color get _color => _colors[engine.id] ?? AppTheme.primary;
  String get _char =>
      engine.name.isNotEmpty ? engine.name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(_char,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800)),
    );
  }
}

// ── Credential config sheet ────────────────────────────────────────────────────

class _CredentialSheet extends StatelessWidget {
  final TranslationEngine engine;
  final List<CredentialField> fields;
  final Map<String, TextEditingController> controllers;
  final VoidCallback onSave;

  const _CredentialSheet({
    required this.engine,
    required this.fields,
    required this.controllers,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
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
            Row(children: [
              Text('配置 ${engine.name}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              _apiDocHint(engine.id),
              style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 20),
            for (final field in fields) ...[
              Text(field.label, style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: controllers[field.key],
                decoration: dec.copyWith(hintText: field.hint),
                style: const TextStyle(fontSize: 14),
                obscureText: field.key.toLowerCase().contains('secret') ||
                    field.key.toLowerCase().contains('key'),
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onSave,
                child: const Text('保存',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _apiDocHint(String engineId) {
    switch (engineId) {
      case 'baidu_api':
        return '在百度翻译开放平台申请：fanyi.baidu.com';
      case 'youdao_api':
        return '在有道智云申请：ai.youdao.com';
      case 'tencent_api':
        return '在腾讯云控制台申请：console.cloud.tencent.com';
      case 'sogou_api':
        return '在搜狗翻译开放平台申请：deepi.sogou.com';
      case 'deepl_api':
        return '在 DeepL 开发者平台申请：www.deepl.com/pro-api';
      default:
        return '';
    }
  }
}

// ── Add / edit custom URL engine sheet ────────────────────────────────────────

class _AddEngineSheet extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController jsonPathCtrl;
  final bool isEditing;
  final VoidCallback onSave;

  const _AddEngineSheet({
    required this.nameCtrl,
    required this.urlCtrl,
    required this.jsonPathCtrl,
    required this.isEditing,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
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
            Row(children: [
              Text(isEditing ? '编辑引擎' : '添加自定义引擎',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 20),

            const Text('引擎名称', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
                controller: nameCtrl,
                decoration: dec.copyWith(hintText: '如 DeepL Free'),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 14),

            const Text('请求 URL（{text} 为待翻译内容占位符）', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: urlCtrl,
              decoration: dec.copyWith(
                  hintText: 'https://api.example.com/translate?q={text}'),
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 14),

            const Text('JSON 响应路径（留空则使用响应体全文）', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: jsonPathCtrl,
              decoration: dec.copyWith(hintText: 'responseData.translatedText'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text('用点号分隔多层路径，如 data.translations.0.text',
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onSave,
                child: Text(isEditing ? '保存' : '添加',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
