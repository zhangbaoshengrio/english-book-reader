import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../services/ai_service.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../services/voice_engine_service.dart';
import '../theme/app_theme.dart';

const _kToolbarItems = [
  ('copy',      Icons.copy_rounded,         '复制'),
  ('highlight', Icons.border_color_rounded, '划线'),
  ('note',      Icons.edit_note_rounded,    '笔记'),
  ('share',     Icons.share_rounded,        '分享'),
];

class FloatingTranslateCard extends StatefulWidget {
  final String originalText;
  final VoidCallback onDismiss;
  final void Function(String action, String text)? onToolbarAction;
  /// Called when user stars an engine result. Receives (phrase, translation, engineId).
  final void Function(String phrase, String translation, String engineId)? onStar;
  /// Called when user unstars an engine result. Receives engineId.
  final void Function(String engineId)? onUnstar;
  /// Called when user taps edit on a starred result. Receives (engineId, translation).
  final void Function(String engineId, String translation)? onEdit;
  /// Which engine results are already starred.
  final Set<String> starredEngineIds;
  /// Whether auto-speak is enabled.
  final bool autoSpeak;

  const FloatingTranslateCard({
    super.key,
    required this.originalText,
    required this.onDismiss,
    this.onToolbarAction,
    this.onStar,
    this.onUnstar,
    this.onEdit,
    this.starredEngineIds = const {},
    this.autoSpeak = false,
  });

  @override
  State<FloatingTranslateCard> createState() => _FloatingTranslateCardState();
}

class _FloatingTranslateCardState extends State<FloatingTranslateCard> {
  List<TranslationEngine> _engines = [];
  /// null = still loading; empty string = error/failed
  final Map<String, String?> _results = {};
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _init();
    if (widget.autoSpeak) TtsService.speak(widget.originalText);
  }

  Future<void> _init() async {
    final engines = await TranslationService.getEnabledEnginesWithAi();
    if (!mounted) return;
    setState(() => _engines = engines);
    // Fire all requests in parallel
    for (final e in engines) {
      _fetchEngine(e.id);
    }
  }

  Future<void> _fetchEngine(String engineId) async {
    if (engineId.startsWith('ai_')) {
      // AI engine: stream response incrementally
      final aiId = engineId.substring(3);
      String accumulated = '';
      await for (final chunk in AiService.queryStream(
          aiId, AiPrompts.sentenceAnalysis(widget.originalText))) {
        if (!mounted) return;
        accumulated += chunk;
        setState(() => _results[engineId] = accumulated);
      }
      if (mounted && accumulated.isEmpty) {
        setState(() => _results[engineId] = '');
      } else if (mounted && accumulated.isNotEmpty) {
        final autoSpeak = await VoiceEngineService.getAiAutoSpeak();
        if (autoSpeak && mounted) TtsService.speakAi(_AiResultBlockState._stripMd(accumulated));
      }
    } else {
      final result =
          await TranslationService.translate(widget.originalText, engineId);
      if (mounted) setState(() => _results[engineId] = result);
    }
  }

  Future<void> _speak() async {
    setState(() => _speaking = true);
    await TtsService.speak(widget.originalText);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final safePad = MediaQuery.of(context).padding;
    // Whole card must not exceed 75% of usable screen height
    final maxCardH = (screenH - safePad.top - safePad.bottom) * 0.75;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: maxCardH),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x30000000), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              _Header(
                autoSpeak: widget.autoSpeak,
                speaking: _speaking,
                onSpeak: _speaking ? null : _speak,
                onDismiss: widget.onDismiss,
              ),
              // ── Toolbar ───────────────────────────────────────────────────
              if (widget.onToolbarAction != null)
                _TranslateToolbar(
                  text: widget.originalText,
                  onAction: widget.onToolbarAction!,
                ),
              // ── Original text ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.originalText,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary,
                          height: 1.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFEEEEEE)),
              // ── Results per engine (Flexible: fills remaining space) ───────
              if (_engines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary)),
                  ),
                )
              else
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _engines.map((engine) {
                        final isAi = engine.type == EngineType.aiEngine;
                        final isLast = engine == _engines.last;
                        final isStarred = widget.starredEngineIds.contains(engine.id);
                        return isAi
                            ? _AiResultBlock(
                                engine: engine,
                                analysis: _results[engine.id],
                                isLast: isLast,
                              )
                            : _ResultBlock(
                                engine: engine,
                                translation: _results[engine.id],
                                isStarred: isStarred,
                                isLast: isLast,
                                onStar: widget.onStar == null ? null : () {
                                  final t = _results[engine.id] ?? '';
                                  widget.onStar!(widget.originalText, t, engine.id);
                                },
                                onUnstar: widget.onUnstar == null ? null
                                    : () => widget.onUnstar!(engine.id),
                                onEdit: (widget.onEdit == null || !isStarred) ? null : () {
                                  final t = _results[engine.id] ?? '';
                                  widget.onEdit!(engine.id, t);
                                },
                              );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool autoSpeak;
  final bool speaking;
  final VoidCallback? onSpeak;
  final VoidCallback onDismiss;

  const _Header({
    required this.autoSpeak,
    required this.speaking,
    required this.onSpeak,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(children: [
        const Icon(Icons.translate_rounded, size: 16, color: AppTheme.primary),
        const SizedBox(width: 6),
        const Text('翻译',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        // Speak button (only when autoSpeak is on)
        if (autoSpeak)
          GestureDetector(
            onTap: onSpeak,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: speaking
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary))
                  : const Icon(Icons.volume_up_rounded,
                      size: 20, color: AppTheme.primary),
            ),
          ),
        // Close
        GestureDetector(
          onTap: onDismiss,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 18, color: AppTheme.textTertiary),
          ),
        ),
      ]),
    );
  }
}

// ── Single engine result block ────────────────────────────────────────────────

class _ResultBlock extends StatelessWidget {
  final TranslationEngine engine;
  final String? translation; // null = loading
  final bool isStarred;
  final bool isLast;
  final VoidCallback? onStar;
  final VoidCallback? onUnstar;
  final VoidCallback? onEdit;

  const _ResultBlock({
    required this.engine,
    required this.translation,
    required this.isStarred,
    required this.isLast,
    this.onStar,
    this.onUnstar,
    this.onEdit,
  });

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
    'mymemory':    Color(0xFF00A67E),
  };

  Color get _color => _colors[engine.id] ?? AppTheme.primary;

  @override
  Widget build(BuildContext context) {
    final loading = translation == null;
    final failed  = !loading && translation!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Engine label + translation text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Engine name tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(engine.name,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _color)),
              ),
              const SizedBox(height: 6),
              // Translation text / loading / failed
              if (loading)
                const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                )
              else if (failed)
                const Text('翻译失败',
                    style: TextStyle(fontSize: 13, color: AppTheme.textTertiary))
              else
                Text(translation!,
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A7A1A),
                        height: 1.6)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Star button + edit link below it
        if (onStar != null || onUnstar != null)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: isStarred ? onUnstar : onStar,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 22,
                    color: isStarred ? const Color(0xFFFFBB00) : AppTheme.textTertiary,
                  ),
                ),
              ),
              if (isStarred && onEdit != null) ...[
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onEdit,
                  child: const Text('编辑',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
      ]),
    );
  }
}

// ── AI result block (markdown, inline with translation results) ───────────────

class _AiResultBlock extends StatefulWidget {
  final TranslationEngine engine;
  final String? analysis; // null = loading
  final bool isLast;

  const _AiResultBlock({
    required this.engine,
    required this.analysis,
    required this.isLast,
  });

  @override
  State<_AiResultBlock> createState() => _AiResultBlockState();
}

class _AiResultBlockState extends State<_AiResultBlock> {
  bool _speaking = false;

  static const _aiColor = Color(0xFF10A37F);

  static final _mdStyle = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.65),
    h1: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    h2: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
    strong: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    em: const TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textSecondary),
    listBullet: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
  );

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await TtsService.stop();
      if (mounted) setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      await TtsService.speakAi(_stripMd(widget.analysis!));
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  void didUpdateWidget(_AiResultBlock old) {
    super.didUpdateWidget(old);
    if (old.analysis != widget.analysis && _speaking) {
      TtsService.stop();
      _speaking = false;
    }
  }

  @override
  void dispose() {
    TtsService.stop();
    super.dispose();
  }

  static String _stripMd(String text) => text
      .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m.group(1) ?? '')
      .replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => m.group(1) ?? '')
      .replaceAll(RegExp(r'#{1,6} ?'), '')
      .replaceAllMapped(RegExp(r'`(.*?)`'), (m) => m.group(1) ?? '')
      .replaceAll(RegExp(r'^\s*[-*+] ', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\. ', multiLine: true), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final loading = widget.analysis == null;
    final failed  = !loading && widget.analysis!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Engine name tag with AI icon + speak button
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 11, color: _aiColor),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _aiColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(widget.engine.name,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _aiColor)),
            ),
            const Spacer(),
            if (!loading && !failed)
              GestureDetector(
                onTap: _toggleSpeak,
                child: Icon(
                  _speaking ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  size: 18,
                  color: _speaking ? _aiColor : _aiColor.withValues(alpha: 0.6),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          if (loading)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _aiColor),
            )
          else if (failed)
            const Text('分析失败，请检查 API Key 或网络连接。',
                style: TextStyle(fontSize: 13, color: AppTheme.textTertiary))
          else
            MarkdownBody(data: widget.analysis!, styleSheet: _mdStyle),
        ],
      ),
    );
  }
}

// ── Action toolbar ────────────────────────────────────────────────────────────

class _TranslateToolbar extends StatelessWidget {
  final String text;
  final void Function(String action, String text) onAction;

  const _TranslateToolbar({required this.text, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: _kToolbarItems.map((item) => Expanded(
          child: GestureDetector(
            onTap: () => onAction(item.$1, text),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(item.$2, size: 16, color: AppTheme.textSecondary),
                const SizedBox(height: 2),
                Text(item.$3, style: const TextStyle(
                    fontSize: 10, color: AppTheme.textSecondary, height: 1)),
              ]),
            ),
          ),
        )).toList(),
      ),
    );
  }
}
