import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
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
  /// Called when user stars a result. Receives (phrase, translation).
  final void Function(String phrase, String translation)? onStar;
  /// Called when user unstars the phrase.
  final VoidCallback? onUnstar;
  /// Called when user taps the edit button (phrase already starred).
  final VoidCallback? onEdit;
  /// Whether the phrase is already starred.
  final bool isStarred;
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
    this.isStarred = false,
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
    final engines = await TranslationService.getEnabledEngines();
    if (!mounted) return;
    setState(() => _engines = engines);
    // Fire all requests in parallel
    for (final e in engines) {
      _fetchEngine(e.id);
    }
  }

  Future<void> _fetchEngine(String engineId) async {
    final result = await TranslationService.translate(widget.originalText, engineId);
    if (mounted) setState(() => _results[engineId] = result);
  }

  Future<void> _speak() async {
    setState(() => _speaking = true);
    await TtsService.speak(widget.originalText);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
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
            // ── Header ──────────────────────────────────────────────────────
            _Header(
              autoSpeak: widget.autoSpeak,
              speaking: _speaking,
              isStarred: widget.isStarred,
              onSpeak: _speaking ? null : _speak,
              onEdit: widget.isStarred ? widget.onEdit : null,
              onDismiss: widget.onDismiss,
            ),
            // ── Toolbar ─────────────────────────────────────────────────────
            if (widget.onToolbarAction != null)
              _TranslateToolbar(
                text: widget.originalText,
                onAction: widget.onToolbarAction!,
              ),
            // ── Original text ────────────────────────────────────────────────
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
            // ── Results per engine ───────────────────────────────────────────
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    children: _engines.map((engine) {
                      final isLast = engine == _engines.last;
                      return _ResultBlock(
                        engine: engine,
                        translation: _results[engine.id],
                        isStarred: widget.isStarred,
                        isLast: isLast,
                        onStar: widget.onStar == null ? null : () {
                          final t = _results[engine.id] ?? '';
                          widget.onStar!(widget.originalText, t);
                        },
                        onUnstar: widget.onUnstar,
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool autoSpeak;
  final bool speaking;
  final bool isStarred;
  final VoidCallback? onSpeak;
  final VoidCallback? onEdit;
  final VoidCallback onDismiss;

  const _Header({
    required this.autoSpeak,
    required this.speaking,
    required this.isStarred,
    required this.onSpeak,
    required this.onEdit,
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
        // Edit button (when starred)
        if (isStarred && onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('编辑',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
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

  const _ResultBlock({
    required this.engine,
    required this.translation,
    required this.isStarred,
    required this.isLast,
    this.onStar,
    this.onUnstar,
  });

  static const _colors = {
    'google':   Color(0xFF4285F4),
    'mymemory': Color(0xFF00A67E),
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
        // Engine label
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
        // Star button
        if (onStar != null || onUnstar != null)
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
      ]),
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
