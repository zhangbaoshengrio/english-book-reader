import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../models/definition.dart';
import '../models/dict_source.dart';
import '../services/tts_service.dart';
import '../services/dictionary_service.dart';
import '../services/ai_service.dart';
import '../services/voice_engine_service.dart';
import '../theme/app_theme.dart';
import '../screens/dict_manager_screen.dart';

class FloatingWordCard extends StatefulWidget {
  final WordLookupResult? result;
  final bool loading;
  final String word;
  final String sentence;
  final String bookTitle;
  final String? savedDefinitionText;
  final List<DictSource> allSources; // ordered, enabled sources (builtin + custom)
  final void Function(Definition def) onStar;
  final void Function() onUnstar;
  final VoidCallback onDismiss;
  final VoidCallback? onEdit;
  final void Function(String action, String word)? onToolbarAction;

  const FloatingWordCard({
    super.key,
    required this.result,
    required this.loading,
    required this.word,
    required this.sentence,
    required this.bookTitle,
    this.savedDefinitionText,
    this.allSources = const [],
    required this.onStar,
    required this.onUnstar,
    required this.onDismiss,
    this.onEdit,
    this.onToolbarAction,
  });

  @override
  State<FloatingWordCard> createState() => _FloatingWordCardState();
}

class _FloatingWordCardState extends State<FloatingWordCard> {
  int _tab = 0;
  static String? _lastTabFilePath; // persist by filePath (stable across renames)

  // AI tab state
  bool _hasAiEngine = false;
  String? _aiResult;       // null = not yet fetched
  bool _aiFetching = false;

  /// All enabled sources to show as tabs, in order.
  List<DictSource> get _sources => widget.allSources;

  // Total tabs = dict sources + (AI tab if available)
  int get _totalTabs => _sources.length + (_hasAiEngine ? 1 : 0);
  bool get _isAiTab => _hasAiEngine && _tab == _sources.length;

  @override
  void initState() {
    super.initState();
    _checkAiEngine();
  }

  Future<void> _checkAiEngine() async {
    final engines = await AiService.getEnabledEngines();
    if (mounted) setState(() => _hasAiEngine = engines.isNotEmpty);
  }

  Future<void> _fetchAiResult({bool reset = false}) async {
    if (_aiFetching) return;
    if (_aiResult != null && !reset) return;
    setState(() { _aiFetching = true; if (reset) _aiResult = null; });

    String accumulated = '';
    await for (final chunk in AiService.lookupWordStream(
        widget.word, widget.sentence)) {
      if (!mounted) return;
      accumulated += chunk;
      // On first chunk: hide spinner and show partial text
      setState(() { _aiFetching = false; _aiResult = accumulated; });
    }

    if (!mounted) return;
    if (accumulated.isEmpty) {
      setState(() {
        _aiResult = '查询失败，请检查 API Key 或网络连接。';
        _aiFetching = false;
      });
    } else {
      // Auto-speak AI result if enabled
      final autoSpeak = await VoiceEngineService.getAiAutoSpeak();
      if (autoSpeak && mounted) TtsService.speakAi(accumulated);
    }
  }

  bool get _isAiResultSaved {
    final saved = widget.savedDefinitionText ?? '';
    if (saved.isEmpty || _aiResult == null) return false;
    // AI result is saved if the savedDefinitionText starts with the AI prefix
    return saved.startsWith('[AI]');
  }

  void _starAiResult() {
    if (_aiResult == null) return;
    // Store AI result as a Definition with a special partOfSpeech marker
    final truncated = _aiResult!.length > 800
        ? _aiResult!.substring(0, 800)
        : _aiResult!;
    widget.onStar(Definition(
      partOfSpeech: 'AI',
      text: '[AI] $truncated',
      chineseText: '',
    ));
  }

  @override
  void didUpdateWidget(FloatingWordCard old) {
    super.didUpdateWidget(old);
    if (widget.loading) return;
    final sources = _sources;
    if (_lastTabFilePath != null) {
      final idx = sources.indexWhere((s) => s.filePath == _lastTabFilePath);
      if (idx >= 0) {
        if (_tab != idx) setState(() => _tab = idx);
        return;
      }
    }
    if (_tab >= _totalTabs && _totalTabs > 0) setState(() => _tab = 0);
  }

  void _openDictManager() {
    widget.onDismiss();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DictManagerScreen()),
    );
  }

  Widget _buildTabContent(DictSource src) {
    final result = widget.result;
    DictResult? dr;
    if (result != null) {
      for (final r in result.dictResults) {
        if (r.name == src.name) { dr = r; break; }
      }
    }
    if (dr == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Text('未找到释义',
            style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
      );
    }
    return _CustomDictContent(
      content: dr.content,
      isHtml: dr.isHtml,
      savedDefinitionText: widget.savedDefinitionText,
      onSaveDefinition: (def) => widget.onStar(def),
      onUnstar: widget.onUnstar,
      onEdit: widget.onEdit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x30000000),
                blurRadius: 24,
                offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
                word: widget.word,
                result: widget.result,
                onDismiss: widget.onDismiss),
            if (widget.onToolbarAction != null)
              _WordToolbar(
                word: widget.word,
                onAction: widget.onToolbarAction!,
              ),
            _LogoTabBar(
              sources: sources,
              hasAiTab: _hasAiEngine,
              selected: _tab,
              onSelect: (i) {
                setState(() => _tab = i);
                if (i < sources.length) {
                  _lastTabFilePath = sources[i].filePath;
                } else {
                  // AI tab selected — auto-fetch
                  _fetchAiResult();
                }
              },
              onSettings: _openDictManager,
            ),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  ),
                ),
              )
            else if (_isAiTab)
              _AiWordPanel(
                fetching: _aiFetching,
                result: _aiResult,
                onFetch: _fetchAiResult,
                onRefresh: () => _fetchAiResult(reset: true),
                isSaved: _isAiResultSaved,
                onStar: _starAiResult,
                onUnstar: widget.onUnstar,
              )
            else if (sources.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Text('请在词典管理中启用词典',
                    style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
              )
            else if (_tab < sources.length)
              _buildTabContent(sources[_tab]),
            if (widget.sentence.isNotEmpty)
              _TranslateRow(sentence: widget.sentence),
          ],
        ),
      ),
    );
  }
}

// ── Word action toolbar ───────────────────────────────────────────────────────

class _WordToolbar extends StatelessWidget {
  final String word;
  final void Function(String action, String word) onAction;

  const _WordToolbar({required this.word, required this.onAction});

  static const _items = [
    ('copy',      Icons.copy_rounded,         '复制'),
    ('highlight', Icons.border_color_rounded, '划线'),
    ('note',      Icons.edit_note_rounded,    '笔记'),
    ('share',     Icons.share_rounded,        '分享'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: _items.map((item) {
          return Expanded(
            child: GestureDetector(
              onTap: () => onAction(item.$1, word),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.$2, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(height: 2),
                  Text(item.$3,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                          height: 1)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Logo tab bar ──────────────────────────────────────────────────────────────

class _LogoTabBar extends StatelessWidget {
  final List<DictSource> sources;
  final bool hasAiTab;
  final int selected;
  final void Function(int) onSelect;
  final VoidCallback onSettings;

  const _LogoTabBar({
    required this.sources,
    required this.hasAiTab,
    required this.selected,
    required this.onSelect,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        border: Border.symmetric(
          horizontal: BorderSide(color: Color(0xFFEEEEEE)),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                ...List.generate(sources.length, (i) {
                  final logo = DictLogo.of(sources[i]);
                  return _LogoTabItem(
                    logo: logo,
                    name: sources[i].name,
                    active: i == selected,
                    onTap: () => onSelect(i),
                  );
                }),
                if (hasAiTab)
                  _AiTabItem(
                    active: selected == sources.length,
                    onTap: () => onSelect(sources.length),
                  ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onSettings,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 46,
            child: Icon(Icons.tune_rounded, size: 17, color: Colors.grey[500]),
          ),
        ),
      ]),
    );
  }
}

class _AiTabItem extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _AiTabItem({required this.active, required this.onTap});

  static const _aiColor = Color(0xFF10A37F); // AI green

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? _aiColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? null
              : Border.all(color: _aiColor.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Center(
          child: Text(
            'AI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : _aiColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoTabItem extends StatelessWidget {
  final DictLogo logo;
  final String name;
  final bool active;
  final VoidCallback onTap;

  const _LogoTabItem(
      {required this.logo,
      required this.name,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(logo.argb);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? null
              : Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Center(
          child: Text(
            logo.char,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : color,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Custom dict panel (native Flutter rendering) ─────────────────────────────

class _CustomDictContent extends StatelessWidget {
  final String content;
  final bool isHtml;
  final String? savedDefinitionText;
  final void Function(Definition def)? onSaveDefinition;
  final VoidCallback? onUnstar;
  final VoidCallback? onEdit;

  const _CustomDictContent({
    required this.content,
    this.isHtml = false,
    this.savedDefinitionText,
    this.onSaveDefinition,
    this.onUnstar,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final defs = isHtml ? _parseMdxHtml(content) : _parsePlainDefs(content);

    if (defs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Text('未找到释义',
            style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
      );
    }

    final saved = savedDefinitionText ?? '';
    final savedPfx = saved.length > 60 ? saved.substring(0, 60) : saved;

    // Sort: starred definition first
    if (savedPfx.isNotEmpty) {
      defs.sort((a, b) {
        final aStarred = a.text.contains(savedPfx) ? 0 : 1;
        final bStarred = b.text.contains(savedPfx) ? 0 : 1;
        return aStarred.compareTo(bStarred);
      });
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.36),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 20),
        itemCount: defs.length,
        itemBuilder: (_, i) {
          final d = defs[i];
          final isSaved =
              savedPfx.isNotEmpty && d.text.contains(savedPfx);
          return _DefRow(
            def: Definition(partOfSpeech: d.pos, text: d.text),
            isSaved: isSaved,
            examples: d.examples,
            cn: d.cn,
            onStar: () {
              final txt = d.text.length > 400
                  ? d.text.substring(0, 400)
                  : d.text;
              onSaveDefinition?.call(
                  Definition(partOfSpeech: d.pos, text: txt, chineseText: d.cn));
            },
            onUnstar: onUnstar ?? () {},
            onEdit: isSaved ? onEdit : null,
          );
        },
      ),
    );
  }
}

// ── MDX HTML → definition list ────────────────────────────────────────────────

class _MdxExample {
  final String en;
  final String cn; // from dict; empty = auto-translate
  const _MdxExample({required this.en, this.cn = ''});
}

class _MdxDef {
  final String pos;
  final String text;
  final String cn; // Chinese meaning from dict (e.g. <deft>)
  final List<_MdxExample> examples;
  const _MdxDef({this.pos = '', required this.text, this.cn = '', this.examples = const []});
}

List<_MdxDef> _parsePlainDefs(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return [];
  return [_MdxDef(text: cleaned)];
}

// ── 21世纪大英汉词典 parser ────────────────────────────────────────────────────
// Structure:
//   ul > li.wordGroup (POS group)
//     span.pos.wordGroup  → part of speech
//     ul.ol.wordGroup > li.wordGroup  (each definition)
//       span.def          → Chinese definition
//       p.additional_en   → English example
//       p.additional      → Chinese translation of example

List<_MdxDef> _parseC21Html(dom.Document doc) {
  final results = <_MdxDef>[];

  for (final defLi in doc.querySelectorAll('.ol > li').toList()) {
    // Chinese definition text
    final defEl = defLi.querySelector('.def');
    if (defEl == null) continue;
    final text = defEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length < 2) continue;

    // POS: go up to ul.ol → li.wordGroup (POS group) → span.pos
    final posGroupLi = defLi.parent?.parent;
    final posEl = posGroupLi?.querySelector('.pos');
    final pos = posEl?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

    // Examples: .additional_en + immediately following .additional
    final examples = <_MdxExample>[];
    for (final enEl in defLi.querySelectorAll('.additional_en').toList()) {
      if (examples.length >= 3) break;
      final enTxt = enEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (enTxt.length <= 4) continue;
      final cnTxt = _nextSiblingCn(enEl, '.additional');
      examples.add(_MdxExample(en: enTxt, cn: cnTxt));
    }

    results.add(_MdxDef(pos: pos, text: text, examples: List.unmodifiable(examples)));
  }
  return results;
}

List<_MdxDef> _parseMdxHtml(String htmlStr) {
  // Multiple MDX entries are separated by \x00 — parse each independently
  // so each entry's docPos is scoped to its own HTML fragment.
  if (htmlStr.contains('\x00')) {
    return htmlStr.split('\x00').expand(_parseMdxHtml).toList();
  }
  try {
    final doc = html_parser.parse(htmlStr);

    // 21世纪大英汉词典: detected by .additional_en class (unique to this dict)
    if (doc.querySelector('.additional_en') != null) {
      return _parseC21Html(doc);
    }

    // Try sense block selectors in priority order
    List<dom.Element> senses = doc.querySelectorAll('li.Sense').toList();
    if (senses.isEmpty) senses = doc.querySelectorAll('li.sense').toList();
    if (senses.isEmpty) senses = doc.querySelectorAll('li.SENSE').toList();
    if (senses.isEmpty) senses = doc.querySelectorAll('.hom').toList();
    if (senses.isEmpty) senses = doc.querySelectorAll('.SENSE-BODY').toList();
    if (senses.isEmpty) senses = doc.querySelectorAll('ol > li').toList();

    if (senses.isEmpty) {
      // No recognisable structure — show whole body as one card
      final body = doc.body;
      if (body == null) return [];
      final text = _domText(body).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.length < 3) return [];
      return [_MdxDef(text: text)];
    }

    // Example group containers (whole block including CN translation children)
    const exGroupSel =
        '.x-g,.EXAMPLE,.example,.exa,.eg,.cit,'
        '.quote,.ExaSent,.EXAMPLE-SENT,.illus,.ColloExa,'
        '.GramExa,.ExaGroup,.example-sentence';
    // Chinese translation tags — must be removed so they don't bleed into defText
    const cnTagSel =
        '.t,.tran,.etran,.chn,.chi,.cn,.translation,.trans,.ctrans';
    const posSel = [
      '.Gram', '.gram', '.GRAM', '.pos', '.POS', '.fl',
      '.type', '.partOfSpeech', '.gramGrp', '.part-of-speech',
    ];

    // Document-level POS fallback (Oxford/OALD: .pos is in .webtop, not in .sense)
    String docPos = '';
    for (final sel in posSel) {
      final found = doc.querySelector(sel);
      if (found != null) {
        docPos = found.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (docPos.isNotEmpty) break;
      }
    }

    final results = <_MdxDef>[];
    for (final el in senses) {
      final clone = el.clone(true);

      // 1. Extract POS; fall back to document-level
      String pos = '';
      for (final sel in posSel) {
        final found = clone.querySelector(sel);
        if (found != null) {
          pos = found.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          found.remove();
          break;
        }
      }
      if (pos.isEmpty) pos = docPos;

      // 1b. Pull out the word-level Chinese definition from <deft> BEFORE
      //     any tag removal, so we can append it back to defText cleanly.
      String wordCn = '';
      for (final deft in clone.querySelectorAll('deft').toList()) {
        final t = deft.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty) { wordCn = t; }
        deft.remove();
      }

      // 2. Extract examples — English text + dict CN translation
      final exGroupEls = clone.querySelectorAll(exGroupSel).toList();
      final bareXEls = clone.querySelectorAll('.x').toList()
          .where((e) => !(e.parent?.classes.contains('x-g') ?? false))
          .toList();

      final examples = <_MdxExample>[];
      for (final e in [...exGroupEls, ...bareXEls]) {
        if (examples.length >= 3) break;
        // English: prefer .x child, else strip CN then read
        final xChild = e.querySelector('.x');
        String enTxt;
        if (xChild != null) {
          enTxt = xChild.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        } else {
          final tmp = e.clone(true);
          for (final s in cnTagSel.split(',')) {
            tmp.querySelectorAll(s.trim()).forEach((c) => c.remove());
          }
          enTxt = tmp.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
        if (enTxt.length <= 4) continue;
        // CN: look inside the example group, then at the immediately following sibling
        String cnTxt = '';
        for (final s in cnTagSel.split(',')) {
          final found = e.querySelector(s.trim());
          if (found != null) {
            cnTxt = found.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (cnTxt.isNotEmpty) break;
          }
        }
        if (cnTxt.isEmpty) {
          // Tag-based CN lookup: Oxford uses <chn>, <at> as actual tags, not classes
          for (final tag in ['chn', 'at', 'tran', 'trans']) {
            final found = e.querySelector(tag);
            if (found != null) {
              cnTxt = found.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (cnTxt.isNotEmpty) break;
            }
          }
        }
        if (cnTxt.isEmpty) {
          // Sibling lookup for bare .x elements (e.g. <span class="x"/><span class="t"/>)
          cnTxt = _nextSiblingCn(e, cnTagSel);
        }
        // Also try sibling tag-based lookup
        if (cnTxt.isEmpty) {
          cnTxt = _nextSiblingTagCn(e, ['chn', 'at', 'tran']);
        }
        examples.add(_MdxExample(en: enTxt, cn: cnTxt));
      }

      // 3. Remove examples, CN tags, and star buttons individually
      //    (splitting avoids CSS selector parsing issues with long combined strings)
      for (final s in '$exGroupSel,.x,.__fs'.split(',')) {
        clone.querySelectorAll(s.trim()).forEach((e) => e.remove());
      }
      for (final s in cnTagSel.split(',')) {
        clone.querySelectorAll(s.trim()).forEach((e) => e.remove());
      }
      // Remove all custom-tag Chinese content by tag name:
      //   <at>  = Oxford example CN wrapper
      //   <chn> = Chinese text node (examples + any other leaked CN)
      //   <ai>  = machine-translation marker inside <chn>
      // Note: <deft> was already extracted above and removed, so wordCn is safe.
      for (final tag in ['at', 'chn', 'ai']) {
        clone.querySelectorAll(tag).forEach((e) => e.remove());
      }
      // Remove topic labels, CEFR level badges, and cross-reference blocks
      // (e.g. "Topics Personal qualities c2", "synonym eccentric")
      const noiseSelectors = [
        '.xrefs', '.xrefs-g',           // synonym / antonym links
        '.topic-g', '.topic', '.topics', // topic labels
        '.cefr', '.lvl',                 // CEFR level (A1–C2)
        '.unbox', '.collapse',           // collapsible extra boxes
      ];
      for (final s in noiseSelectors) {
        clone.querySelectorAll(s).forEach((e) => e.remove());
      }

      // 4. Remaining clone text = English definition only (all CN tags removed).
      //    wordCn is stored separately in the cn field, not mixed into defText.
      final defText = clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (defText.length < 3) continue;
      results.add(_MdxDef(pos: pos, text: defText, cn: wordCn, examples: List.unmodifiable(examples)));
    }
    return results;
  } catch (_) {
    return [];
  }
}

/// Return the text of the first immediately-following sibling whose tag name
/// is in [tags] (e.g. ['chn', 'at']).
String _nextSiblingTagCn(dom.Element el, List<String> tags) {
  final parent = el.parent;
  if (parent == null) return '';
  final tagSet = tags.toSet();
  bool passed = false;
  for (final child in parent.children) {
    if (child == el) { passed = true; continue; }
    if (!passed) continue;
    if (tagSet.contains(child.localName?.toLowerCase())) {
      return child.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    break;
  }
  return '';
}

/// Return the text of the first immediately-following sibling that matches any
/// selector in [cnTagSel] (comma-separated class selectors like '.t,.tran').
String _nextSiblingCn(dom.Element el, String cnTagSel) {
  final parent = el.parent;
  if (parent == null) return '';
  final classes = cnTagSel
      .split(',')
      .map((s) => s.trim().replaceFirst('.', ''))
      .toSet();
  bool passed = false;
  for (final child in parent.children) {
    if (child == el) { passed = true; continue; }
    if (!passed) continue;
    if (child.classes.any(classes.contains)) {
      return child.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    break; // only check the immediately next sibling
  }
  return '';
}

String _domText(dom.Node node) {
  if (node is dom.Text) return node.text;
  if (node is dom.Element) {
    if (const {'script', 'style', 'head'}.contains(node.localName)) {
      return '';
    }
    if (node.localName == 'br') return '\n';
    return node.nodes.map(_domText).join('');
  }
  return '';
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String word;
  final WordLookupResult? result;
  final VoidCallback onDismiss;
  const _Header(
      {required this.word, required this.result, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final phonetic = result?.phonetic ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(word,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
              if (phonetic.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(phonetic,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary)),
              ],
            ],
          ),
        ),
        GestureDetector(
          onTap: () => TtsService.speak(word),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.volume_up_rounded,
                size: 20, color: AppTheme.primary),
          ),
        ),
        GestureDetector(
          onTap: onDismiss,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(Icons.close_rounded,
                size: 20, color: AppTheme.textTertiary),
          ),
        ),
      ]),
    );
  }
}

// ── Definition card row ───────────────────────────────────────────────────────

class _DefRow extends StatelessWidget {
  final Definition def;
  final bool isSaved;
  final List<_MdxExample> examples;
  final String cn; // Chinese meaning to display under definition
  final VoidCallback onStar;
  final VoidCallback onUnstar;
  final VoidCallback? onEdit;

  const _DefRow({
    required this.def,
    required this.isSaved,
    this.examples = const [],
    this.cn = '',
    required this.onStar,
    required this.onUnstar,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSaved ? const Color(0xFFF0FFF5) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSaved ? const Color(0xFF9DDBB8) : const Color(0xFFE8E8E8),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Left: content ────────────────────────────────────────────────
          Expanded(child: _buildContent()),
          // ── Right: star + edit ───────────────────────────────────────────
          const SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: isSaved ? onUnstar : onStar,
              child: Icon(
                  isSaved ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 22,
                  color: isSaved
                      ? const Color(0xFFFFBB00)
                      : AppTheme.textTertiary),
            ),
            if (isSaved && onEdit != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onEdit,
                child: const Text('编辑',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // POS — blue text, slightly smaller than definition
      if (def.partOfSpeech.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(def.partOfSpeech,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ),

      // Definition text (bold)
      Text(def.text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              height: 1.45)),

      // Chinese meaning from dict
      if (cn.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(cn,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.4)),
        ),

      // Examples — use dict's own CN translation; fall back to auto-translate
      for (final ex in examples) _ExampleRow(text: ex.en, dictCn: ex.cn),
    ]);
  }
}

// In-memory cache for example sentence translations (avoids repeat network calls)
final _exampleCnCache = <String, String>{};

// ── Example row with auto CN translation ─────────────────────────────────────

class _ExampleRow extends StatefulWidget {
  final String text;
  final String dictCn; // CN translation from dict; empty = auto-translate
  const _ExampleRow({required this.text, this.dictCn = ''});

  @override
  State<_ExampleRow> createState() => _ExampleRowState();
}

class _ExampleRowState extends State<_ExampleRow> {
  String? _cn;

  @override
  void initState() {
    super.initState();
    if (widget.dictCn.isNotEmpty) {
      _cn = widget.dictCn;
    } else if (_exampleCnCache.containsKey(widget.text)) {
      _cn = _exampleCnCache[widget.text];
    } else {
      _fetchCn();
    }
  }

  @override
  void didUpdateWidget(_ExampleRow old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.dictCn != widget.dictCn) {
      if (widget.dictCn.isNotEmpty) {
        setState(() => _cn = widget.dictCn);
      } else if (_exampleCnCache.containsKey(widget.text)) {
        setState(() => _cn = _exampleCnCache[widget.text]);
      } else {
        setState(() => _cn = null);
        _fetchCn();
      }
    }
  }

  Future<void> _fetchCn() async {
    final cn = await DictionaryService.translateSentence(widget.text);
    if (cn.isNotEmpty) _exampleCnCache[widget.text] = cn;
    if (mounted && cn.isNotEmpty) setState(() => _cn = cn);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('► ',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textTertiary,
                  height: 1.4)),
          Expanded(
            child: Text(widget.text,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textTertiary,
                    height: 1.4)),
          ),
        ]),
        if (_cn != null && _cn!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 2),
            child: Text(_cn!,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A8040),
                    height: 1.4)),
          ),
      ]),
    );
  }
}

// ── AI word panel ──────────────────────────────────────────────────────────────

class _AiWordPanel extends StatefulWidget {
  final bool fetching;
  final String? result;
  final VoidCallback onFetch;
  final VoidCallback onRefresh;
  final bool isSaved;
  final VoidCallback onStar;
  final VoidCallback onUnstar;

  const _AiWordPanel({
    required this.fetching,
    required this.result,
    required this.onFetch,
    required this.onRefresh,
    required this.isSaved,
    required this.onStar,
    required this.onUnstar,
  });

  @override
  State<_AiWordPanel> createState() => _AiWordPanelState();
}

class _AiWordPanelState extends State<_AiWordPanel> {
  bool _speaking = false;

  static const _aiColor = Color(0xFF10A37F);
  static final _mdStyle = MarkdownStyleSheet(
    p: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6),
    h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
    strong: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
    em: const TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textPrimary),
    code: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppTheme.primary),
    listBullet: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
  );

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await TtsService.stop();
      if (mounted) setState(() => _speaking = false);
    } else {
      setState(() => _speaking = true);
      await TtsService.speakAi(widget.result!);
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  void didUpdateWidget(_AiWordPanel old) {
    super.didUpdateWidget(old);
    // Stop speaking if result changes (refresh)
    if (old.result != widget.result && _speaking) {
      TtsService.stop();
      _speaking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fetching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _aiColor),
          ),
        ),
      );
    }

    if (widget.result == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: GestureDetector(
          onTap: widget.onFetch,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _aiColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _aiColor.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: _aiColor),
              const SizedBox(width: 6),
              Text('AI 智能释义',
                  style: TextStyle(
                      fontSize: 13,
                      color: _aiColor,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.36),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 13, color: _aiColor),
              const SizedBox(width: 4),
              Text('AI 释义',
                  style: TextStyle(
                      fontSize: 11,
                      color: _aiColor,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: widget.onRefresh,
                child: Text('重新查询',
                    style: TextStyle(
                        fontSize: 11,
                        color: _aiColor.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              // Speak button
              GestureDetector(
                onTap: _toggleSpeak,
                child: Icon(
                  _speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                  size: 18,
                  color: _speaking ? Colors.redAccent : _aiColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              // Star button
              GestureDetector(
                onTap: widget.isSaved ? widget.onUnstar : widget.onStar,
                child: Icon(
                  widget.isSaved ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 22,
                  color: widget.isSaved
                      ? const Color(0xFFFFBB00)
                      : AppTheme.textTertiary,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            MarkdownBody(data: widget.result!, styleSheet: _mdStyle),
          ],
        ),
      ),
    );
  }
}

// ── Sentence translate row ────────────────────────────────────────────────────

class _TranslateRow extends StatefulWidget {
  final String sentence;
  const _TranslateRow({required this.sentence});
  @override
  State<_TranslateRow> createState() => _TranslateRowState();
}

class _TranslateRowState extends State<_TranslateRow> {
  String? _translation;
  bool _translating = false;

  Future<void> _translate() async {
    setState(() => _translating = true);
    final result = await DictionaryService.translateSentence(widget.sentence);
    if (mounted) {
      setState(() {
        _translation = result;
        _translating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              widget.sentence.length > 100
                  ? '${widget.sentence.substring(0, 100)}…'
                  : widget.sentence,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                  fontStyle: FontStyle.italic,
                  height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          if (!_translating && _translation == null)
            GestureDetector(
              onTap: _translate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('翻译',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            )
          else if (_translating)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppTheme.primary)),
        ]),
        if (_translation != null && _translation!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_translation!,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1A7A1A),
                  height: 1.5)),
        ],
      ]),
    );
  }
}
