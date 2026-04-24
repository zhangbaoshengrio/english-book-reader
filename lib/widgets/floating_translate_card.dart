import 'package:flutter/material.dart';
import '../services/dictionary_service.dart';
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
  /// Called when user stars the phrase. Receives (phrase, translation).
  final void Function(String phrase, String translation)? onStar;
  /// Called when user unstars the phrase.
  final VoidCallback? onUnstar;
  /// Whether the phrase is already starred.
  final bool isStarred;
  /// Whether auto-speak is enabled (controls visibility of speak button and auto-play).
  final bool autoSpeak;

  const FloatingTranslateCard({
    super.key,
    required this.originalText,
    required this.onDismiss,
    this.onToolbarAction,
    this.onStar,
    this.onUnstar,
    this.isStarred = false,
    this.autoSpeak = false,
  });

  @override
  State<FloatingTranslateCard> createState() => _FloatingTranslateCardState();
}

class _FloatingTranslateCardState extends State<FloatingTranslateCard> {
  String? _translation;
  bool _loading = true;

  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    if (widget.autoSpeak) {
      TtsService.speak(widget.originalText);
    }
  }

  Future<void> _speak() async {
    setState(() => _speaking = true);
    await TtsService.speak(widget.originalText);
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _fetch() async {
    final r = await DictionaryService.translateSentence(widget.originalText);
    if (mounted) setState(() { _translation = r; _loading = false; });
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
            // Header
            Container(
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
                // Speak button (visible only when autoSpeak is on)
                if (widget.autoSpeak)
                  GestureDetector(
                    onTap: _speaking ? null : _speak,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _speaking
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.primary))
                          : const Icon(Icons.volume_up_rounded,
                              size: 20, color: AppTheme.primary),
                    ),
                  ),
                // Star button
                if (widget.onStar != null || widget.onUnstar != null)
                  GestureDetector(
                    onTap: () {
                      if (widget.isStarred) {
                        widget.onUnstar?.call();
                      } else {
                        widget.onStar?.call(
                          widget.originalText,
                          _translation ?? '',
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        widget.isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 20,
                        color: widget.isStarred ? const Color(0xFFFFBB00) : AppTheme.textTertiary,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 18, color: AppTheme.textTertiary),
                  ),
                ),
              ]),
            ),
            // Toolbar
            if (widget.onToolbarAction != null)
              _TranslateToolbar(
                text: widget.originalText,
                onAction: widget.onToolbarAction!,
              ),
            // Original
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 90),
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
            // Translation
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)),
                      ))
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(
                          (_translation?.isNotEmpty == true)
                              ? _translation!
                              : '翻译失败，请检查网络',
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1A7A1A),
                              height: 1.6),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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
