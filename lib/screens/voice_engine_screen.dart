import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/voice_engine_service.dart';
import '../theme/app_theme.dart';

class VoiceEngineScreen extends StatefulWidget {
  const VoiceEngineScreen({super.key});

  @override
  State<VoiceEngineScreen> createState() => _VoiceEngineScreenState();
}

class _VoiceEngineScreenState extends State<VoiceEngineScreen> {
  List<VoiceEngine> _engines = [];
  String _activeId = 'builtin';
  bool _autoSpeak = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      VoiceEngineService.getEngines(),
      VoiceEngineService.getActiveEngineId(),
      VoiceEngineService.getAutoSpeak(),
    ]);
    if (mounted) {
      setState(() {
        _engines = results[0] as List<VoiceEngine>;
        _activeId = results[1] as String;
        _autoSpeak = results[2] as bool;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await VoiceEngineService.saveEngines(_engines);
  }

  Future<void> _setActive(String id) async {
    setState(() => _activeId = id);
    await VoiceEngineService.setActiveEngineId(id);
  }

  void _updateEngineSpeed(int index, double speed) {
    setState(() {
      _engines[index] = _engines[index].copyWith(speed: speed);
    });
  }

  Future<void> _commitEngineSpeed(int index, double speed) async {
    _engines[index] = _engines[index].copyWith(speed: speed);
    await _save();
    // If builtin, update flutter_tts speed immediately
    if (_engines[index].type == VoiceEngineType.builtinTts) {
      await TtsService.setSpeed(speed);
      // Also update legacy setting for backward compat
      await SettingsService.setTtsSpeed(speed);
    }
  }

  Future<void> _deleteEngine(VoiceEngine engine) async {
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
      if (_activeId == engine.id) await _setActive('builtin');
      setState(() => _engines.removeWhere((e) => e.id == engine.id));
      await _save();
    }
  }

  void _showCredentialSheet(VoiceEngine engine) {
    final fields = VoiceEngine.credentialFields[engine.id] ?? [];
    final controllers = {
      for (final f in fields)
        f.key: TextEditingController(text: engine.credentials[f.key] ?? ''),
    };
    String selectedVoice = engine.voiceParam.isNotEmpty
        ? engine.voiceParam
        : (engine.id == 'openai_tts' ? 'alloy' : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _CredentialSheet(
            engine: engine,
            fields: fields,
            controllers: controllers,
            selectedVoice: selectedVoice,
            onVoiceChanged: (v) => setSheetState(() => selectedVoice = v),
            onSave: () async {
              final creds = {
                for (final f in fields) f.key: controllers[f.key]!.text.trim(),
              };
              final nav = Navigator.of(ctx);
              await VoiceEngineService.saveCredentials(engine.id, creds);
              // Save voice selection
              final engines = await VoiceEngineService.getEngines();
              final idx = engines.indexWhere((e) => e.id == engine.id);
              if (idx >= 0) {
                engines[idx] = engines[idx].copyWith(voiceParam: selectedVoice);
                await VoiceEngineService.saveEngines(engines);
              }
              await _load();
              if (mounted) nav.pop();
            },
          ),
        ),
      ),
    );
  }

  void _showAddSheet({VoiceEngine? editing}) {
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    final urlCtrl  = TextEditingController(text: editing?.urlTemplate ?? '');
    final voiceCtrl = TextEditingController(text: editing?.voiceParam ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddEngineSheet(
          nameCtrl: nameCtrl,
          urlCtrl: urlCtrl,
          voiceCtrl: voiceCtrl,
          isEditing: editing != null,
          onSave: () async {
            final name = nameCtrl.text.trim();
            final url  = urlCtrl.text.trim();
            if (name.isEmpty || url.isEmpty) return;
            final nav = Navigator.of(ctx);
            await VoiceEngineService.saveCustomEngine(
              id: editing?.id,
              name: name,
              urlTemplate: url,
              voiceParam: voiceCtrl.text.trim(),
            );
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
        title: const Text('语音引擎'),
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
                // ── 自动发音 toggle ─────────────────────────────────────────
                Container(
                  color: Colors.white,
                  child: SwitchListTile(
                    title: const Text('自动发音',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: const Text('点击单词时自动朗读',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    value: _autoSpeak,
                    activeTrackColor: AppTheme.primary.withValues(alpha: 0.4),
                    activeThumbColor: AppTheme.primary,
                    onChanged: (v) {
                      setState(() => _autoSpeak = v);
                      VoiceEngineService.setAutoSpeak(v);
                      // Sync legacy key so reader_screen still works
                      SettingsService.setAutoSpeak(v);
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: const Text(
                    '选择当前使用的语音引擎；官方 API 引擎需点击钥匙图标配置密钥',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _engines.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 1),
                    itemBuilder: (context, index) {
                      final engine = _engines[index];
                      final isCustom = engine.type == VoiceEngineType.customUrl;
                      final isApiEngine = engine.type == VoiceEngineType.openaiApi;
                      final hasSpeed = engine.type == VoiceEngineType.builtinTts ||
                          engine.type == VoiceEngineType.openaiApi;
                      return _EngineRow(
                        engine: engine,
                        isActive: engine.id == _activeId,
                        isFirst: index == 0,
                        isLast: index == _engines.length - 1,
                        showSpeedSlider: hasSpeed,
                        onSelect: () => _setActive(engine.id),
                        onSpeedChanged: (v) => _updateEngineSpeed(index, v),
                        onSpeedChangeEnd: (v) => _commitEngineSpeed(index, v),
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
  final VoiceEngine engine;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  final bool showSpeedSlider;
  final VoidCallback onSelect;
  final void Function(double) onSpeedChanged;
  final void Function(double) onSpeedChangeEnd;
  final VoidCallback? onConfigure;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EngineRow({
    required this.engine,
    required this.isActive,
    required this.isFirst,
    required this.isLast,
    required this.showSpeedSlider,
    required this.onSelect,
    required this.onSpeedChanged,
    required this.onSpeedChangeEnd,
    this.onConfigure,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBuiltin = engine.type == VoiceEngineType.builtinTts;
    final speedMin = isBuiltin ? 0.3 : 0.25;
    final speedMax = isBuiltin ? 1.5 : 4.0;
    final speedDivisions = isBuiltin ? 12 : 31;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(12) : Radius.zero,
            bottom: isLast ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const SizedBox(width: 16),
              // Active indicator
              Icon(
                isActive ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: isActive ? AppTheme.primary : AppTheme.textTertiary,
              ),
              const SizedBox(width: 12),
              // Badge
              _VoiceBadge(engine: engine),
              const SizedBox(width: 10),
              // Name + subtitle
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Text(engine.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 6),
                        _TypeTag(engine.type),
                      ]),
                      const SizedBox(height: 2),
                      _subtitle(engine),
                    ],
                  ),
                ),
              ),
              // Configure (openai)
              if (onConfigure != null)
                IconButton(
                  icon: const Icon(Icons.key_rounded, size: 18),
                  color: AppTheme.textSecondary,
                  tooltip: '配置密钥',
                  onPressed: onConfigure,
                ),
              // Edit + delete (custom)
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
              const SizedBox(width: 8),
            ]),
            // Speed slider
            if (showSpeedSlider) ...[
              const Divider(height: 1, indent: 60, endIndent: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  const SizedBox(width: 34),
                  const Icon(Icons.speed_rounded, size: 16, color: AppTheme.textTertiary),
                  const SizedBox(width: 8),
                  const Text('语速', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: AppTheme.primary,
                        thumbColor: AppTheme.primary,
                        overlayColor: AppTheme.primary.withValues(alpha: 0.12),
                        inactiveTrackColor: const Color(0xFFE0E0E0),
                      ),
                      child: Slider(
                        value: engine.speed.clamp(speedMin, speedMax),
                        min: speedMin,
                        max: speedMax,
                        divisions: speedDivisions,
                        onChanged: onSpeedChanged,
                        onChangeEnd: onSpeedChangeEnd,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      engine.speed.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subtitle(VoiceEngine engine) {
    if (engine.type == VoiceEngineType.builtinTts) {
      return const Text('使用系统 TTS 引擎，无需配置',
          style: TextStyle(fontSize: 11, color: AppTheme.textTertiary));
    }
    if (engine.type == VoiceEngineType.openaiApi) {
      final hasKey = (engine.credentials['apiKey'] ?? '').isNotEmpty;
      final voice = engine.voiceParam.isNotEmpty ? engine.voiceParam : 'alloy';
      if (hasKey) {
        return Text('已配置 · 音色：$voice',
            style: TextStyle(fontSize: 11, color: Colors.green.shade600));
      }
      return const Text('未配置（点击钥匙图标配置）',
          style: TextStyle(fontSize: 11, color: AppTheme.textTertiary));
    }
    if (engine.urlTemplate.isNotEmpty) {
      final url = engine.urlTemplate.length > 38
          ? '${engine.urlTemplate.substring(0, 38)}…'
          : engine.urlTemplate;
      return Text(url,
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
    return const SizedBox.shrink();
  }
}

// ── Type tag ───────────────────────────────────────────────────────────────────

class _TypeTag extends StatelessWidget {
  final String type;
  const _TypeTag(this.type);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      VoiceEngineType.builtinTts => ('内置', const Color(0xFF34A853)),
      VoiceEngineType.openaiApi  => ('API',  const Color(0xFFFF9800)),
      _                          => ('自定义', AppTheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Voice badge ────────────────────────────────────────────────────────────────

class _VoiceBadge extends StatelessWidget {
  final VoiceEngine engine;
  const _VoiceBadge({required this.engine});

  static const _colors = {
    'builtin':    Color(0xFF607D8B),
    'openai_tts': Color(0xFF10A37F),
  };

  Color get _color => _colors[engine.id] ?? AppTheme.primary;
  String get _icon => switch (engine.type) {
    VoiceEngineType.builtinTts => '🔊',
    VoiceEngineType.openaiApi  => 'G',
    _                          => engine.name.isNotEmpty ? engine.name[0].toUpperCase() : '?',
  };
  bool get _isEmoji => engine.type == VoiceEngineType.builtinTts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _isEmoji ? _color.withValues(alpha: 0.12) : _color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(_icon,
          style: TextStyle(
              color: _isEmoji ? _color : Colors.white,
              fontSize: _isEmoji ? 18 : 14,
              fontWeight: FontWeight.w800)),
    );
  }
}

// ── Credential config sheet ────────────────────────────────────────────────────

class _CredentialSheet extends StatelessWidget {
  final VoiceEngine engine;
  final List<VoiceCredentialField> fields;
  final Map<String, TextEditingController> controllers;
  final String selectedVoice;
  final void Function(String) onVoiceChanged;
  final VoidCallback onSave;

  const _CredentialSheet({
    required this.engine,
    required this.fields,
    required this.controllers,
    required this.selectedVoice,
    required this.onVoiceChanged,
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Text('配置 ${engine.name}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: AppTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('在 platform.openai.com 申请 API Key',
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
            const SizedBox(height: 20),

            for (final field in fields) ...[
              Text(field.label, style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: controllers[field.key],
                decoration: dec.copyWith(hintText: field.hint),
                style: const TextStyle(fontSize: 14),
                obscureText: field.key.toLowerCase().contains('key'),
              ),
              const SizedBox(height: 14),
            ],

            // Voice picker (OpenAI only)
            if (engine.id == 'openai_tts') ...[
              const Text('音色', style: labelStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VoiceEngine.openaiVoices.map((v) {
                  final selected = v == selectedVoice;
                  return GestureDetector(
                    onTap: () => onVoiceChanged(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.12)
                            : const Color(0xFFF3F3F3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? AppTheme.primary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(v,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? AppTheme.primary : AppTheme.textSecondary)),
                    ),
                  );
                }).toList(),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onSave,
                child: const Text('保存',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add / edit custom URL engine sheet ────────────────────────────────────────

class _AddEngineSheet extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController voiceCtrl;
  final bool isEditing;
  final VoidCallback onSave;

  const _AddEngineSheet({
    required this.nameCtrl,
    required this.urlCtrl,
    required this.voiceCtrl,
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Text(isEditing ? '编辑引擎' : '添加自定义语音引擎',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: AppTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 20),

            const Text('引擎名称', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              decoration: dec.copyWith(hintText: '如 自建 TTS'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 14),

            const Text('请求 URL（{text} 为文本占位符，{voice} 为音色占位符）', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: urlCtrl,
              decoration: dec.copyWith(
                  hintText: 'https://api.example.com/tts?text={text}&voice={voice}'),
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 6),
            const Text('请求返回 MP3/WAV 音频数据',
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
            const SizedBox(height: 14),

            const Text('音色参数（可选）', style: labelStyle),
            const SizedBox(height: 6),
            TextField(
              controller: voiceCtrl,
              decoration: dec.copyWith(hintText: '如 zh-CN-XiaoxiaoNeural'),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onSave,
                child: Text(isEditing ? '保存' : '添加',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
