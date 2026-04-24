import 'package:flutter/material.dart';
import '../models/definition.dart';
import '../models/vocab_entry.dart';
import '../services/dictionary_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet that shows dictionary definitions for a tapped word.
/// The user selects the meaning that fits the reading context, then saves it.
class DefinitionSheet extends StatefulWidget {
  final String word;
  final String contextSentence;
  final String bookTitle;
  final bool alreadySaved;

  const DefinitionSheet({
    super.key,
    required this.word,
    required this.contextSentence,
    required this.bookTitle,
    this.alreadySaved = false,
  });

  @override
  State<DefinitionSheet> createState() => _DefinitionSheetState();
}

class _DefinitionSheetState extends State<DefinitionSheet> {
  WordLookupResult? _result;
  bool _loading = true;
  int? _selectedIdx;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    final r = await DictionaryService.lookup(widget.word);
    if (mounted) setState(() { _result = r; _loading = false; });
  }

  void _save() {
    if (_selectedIdx == null || _result == null) return;
    final def = _result!.definitions[_selectedIdx!];
    Navigator.pop(context, VocabEntry(
      word:         widget.word,
      definition:   def.text,
      partOfSpeech: def.partOfSpeech,
      sentence:     widget.contextSentence,
      source:       widget.bookTitle,
      addedAt:      DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom
                 + MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Word + phonetic ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(widget.word,
                    style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    )),
                const SizedBox(width: 10),
                if (!_loading &&
                    _result?.phonetic != null &&
                    _result!.phonetic.isNotEmpty)
                  Text(_result!.phonetic,
                      style: const TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary,
                      )),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Context sentence ─────────────────────────────────────────────
          if (widget.contextSentence.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '"${widget.contextSentence}"',
                  style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic, height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          const SizedBox(height: 10),
          const Divider(height: 1),

          // ── Definitions ───────────────────────────────────────────────────
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_result == null ||
                        !_result!.found ||
                        _result!.definitions.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 40, color: AppTheme.textTertiary),
                            const SizedBox(height: 12),
                            const Text('No definition found',
                                style: TextStyle(color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            const Text('Check your internet connection',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textTertiary)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        itemCount: _result!.definitions.length,
                        separatorBuilder: (context, i) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _DefCard(
                          definition: _result!.definitions[i],
                          selected:   _selectedIdx == i,
                          disabled:   widget.alreadySaved,
                          onTap:      widget.alreadySaved
                              ? null
                              : () => setState(() => _selectedIdx = i),
                        ),
                      ),
          ),

          // ── Save button ───────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
            child: SizedBox(
              width: double.infinity,
              child: widget.alreadySaved
                  ? ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          color: Colors.white),
                      label: const Text('Already Saved',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppTheme.success.withValues(alpha: 0.75),
                        disabledBackgroundColor:
                            AppTheme.success.withValues(alpha: 0.75),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _selectedIdx != null ? _save : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _selectedIdx == null
                            ? 'Tap a definition to select it'
                            : 'Save to Vocabulary',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual definition card
// ─────────────────────────────────────────────────────────────────────────────
class _DefCard extends StatelessWidget {
  final Definition definition;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _DefCard({
    required this.definition,
    required this.selected,
    required this.disabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.07)
              : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // POS badge
                  if (definition.partOfSpeech.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.14)
                            : const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        definition.partOfSpeech,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // Definition text
                  Text(
                    definition.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                      height: 1.55,
                    ),
                  ),
                  // Example sentence
                  if (definition.example.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '"${definition.example}"',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Checkmark
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 10, top: 2),
                child: Icon(Icons.check_circle_rounded,
                    color: AppTheme.primary, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}
