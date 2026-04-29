import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/definition.dart';
import '../models/dict_source.dart';
import '../models/reader_note.dart';
import '../models/vocab_entry.dart';
import '../services/book_parser.dart';
import '../services/database_service.dart';
import '../services/dictionary_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import '../widgets/floating_word_card.dart';
import '../widgets/floating_translate_card.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  final List<String> paragraphs;

  const ReaderScreen({super.key, required this.book, required this.paragraphs});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _page;
  Set<String> _vocabSet = {};
  Map<String, String> _vocabDefMap = {};
  List<DictSource> _activeSources = [];
  final _scroll = ScrollController();
  late PageController _pageCtrl;
  Timer? _scrollSaveTimer;

  // Overlay state
  OverlayEntry? _overlayEntry;
  String _overlayHitKey = '';
  WordLookupResult? _overlayResult;
  bool _overlayLoading = false;
  String _translateText = '';
  String _translateParaText = ''; // paragraph containing the selected phrase
  Offset _tapPos = Offset.zero;
  // Which engine IDs are starred for the current translate text
  Set<String> _translateStarredEngines = {};

  // Para keys — used to call selectWord / clearSelection on each paragraph
  final _paraKeys = <int, GlobalKey<_ReaderParagraphState>>{};
  // Track which paragraph owns the current word selection
  int _selectedParaIdx = -1;

  // Bookmarks & notes
  List<Bookmark>   _bookmarks = [];
  List<ReaderNote> _readerNotes = [];

  // Settings
  bool   _autoSpeak     = false;
  bool   _autoTranslate = true;
  double _fontSize      = 18;
  double _lineHeight    = 1.9;
  double _margin        = 22;
  String _theme         = ReaderTheme.paper;
  String _fontFamily    = 'Georgia';
  String _pageTurnStyle = PageTurnStyle.scroll;

  Color get _bgColor {
    switch (_theme) {
      case ReaderTheme.white: return Colors.white;
      case ReaderTheme.dark:  return const Color(0xFF1C1C1E);
      case ReaderTheme.green: return AppTheme.readerBgGreen;
      default:                return AppTheme.readerBg;
    }
  }

  Color get _textColor {
    return _theme == ReaderTheme.dark
        ? const Color(0xFFE5E5E7)
        : AppTheme.textPrimary;
  }

  // ── Dynamic pagination for swipe mode ────────────────────────────────────
  // Computed lazily when swipe mode is active and layout size is known.
  List<List<String>> _swipePages = [];
  double _swipePagesForHeight = -1;
  double _swipePagesForWidth  = -1;
  double _swipePagesForFontSize   = -1;
  double _swipePagesForLineHeight = -1;

  int get _totalPages => _pageTurnStyle == PageTurnStyle.swipe && _swipePages.isNotEmpty
      ? _swipePages.length
      : BookParser.pageCount(widget.paragraphs.length);

  List<String> get _curParas => _pageTurnStyle == PageTurnStyle.swipe && _swipePages.isNotEmpty
      ? (_page < _swipePages.length ? _swipePages[_page] : [])
      : BookParser.getPage(widget.paragraphs, _page);

  /// Compute dynamic page list by measuring each paragraph with TextPainter.
  /// Returns the new pages; does NOT call setState.
  List<List<String>> _computeSwipePages(double pageHeight, double pageWidth) {
    const double paraSpacing = 24.0; // matches Padding(bottom: 24) in _buildParaWidget

    final pages = <List<String>>[];
    var currentPage = <String>[];
    var usedHeight = 0.0;

    for (final para in widget.paragraphs) {
      final tp = TextPainter(
        text: TextSpan(
          text: para,
          style: TextStyle(
            fontSize: _fontSize,
            height: _lineHeight,
            fontFamily: _fontFamily,
            letterSpacing: 0.15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: pageWidth);

      final paraHeight = tp.height + paraSpacing;

      if (currentPage.isEmpty) {
        currentPage.add(para);
        usedHeight = paraHeight;
      } else if (usedHeight + paraHeight <= pageHeight) {
        currentPage.add(para);
        usedHeight += paraHeight;
      } else {
        pages.add(currentPage);
        currentPage = [para];
        usedHeight = paraHeight;
      }
    }
    if (currentPage.isNotEmpty) pages.add(currentPage);
    return pages;
  }

  /// Called from LayoutBuilder — computes pages if layout/font changed,
  /// then schedules setState if the result differs.
  void _maybeRebuildSwipePages(double pageHeight, double pageWidth) {
    if (_swipePagesForHeight    == pageHeight &&
        _swipePagesForWidth     == pageWidth  &&
        _swipePagesForFontSize   == _fontSize   &&
        _swipePagesForLineHeight == _lineHeight) return;

    final newPages = _computeSwipePages(pageHeight, pageWidth);

    _swipePagesForHeight     = pageHeight;
    _swipePagesForWidth      = pageWidth;
    _swipePagesForFontSize   = _fontSize;
    _swipePagesForLineHeight = _lineHeight;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _swipePages = newPages;
        if (_page >= newPages.length) {
          _page = (newPages.length - 1).clamp(0, newPages.length - 1);
        }
      });
      // Jump PageController to correct page after rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients && _pageCtrl.page?.round() != _page) {
          _pageCtrl.jumpToPage(_page);
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _page = widget.book.lastPage.clamp(0, _totalPages - 1);
    _pageCtrl = PageController(initialPage: _page);
    _scroll.addListener(_onScrolled);
    _refreshVocab();
    _refreshSources();
    _loadSettings();
    _refreshBookmarksAndNotes();
  }

  Future<void> _loadSettings() async {
    final bookId = widget.book.id ?? 0;
    final results = await Future.wait([
      SettingsService.getAutoSpeak(),
      SettingsService.getFontSize(),
      SettingsService.getLineHeight(),
      SettingsService.getTheme(),
      SettingsService.getFontFamily(),
      SettingsService.getMargin(),
      SettingsService.getPageTurnStyle(),
      SettingsService.getScrollOffset(bookId),
      SettingsService.getAutoTranslate(),
    ]);
    if (!mounted) return;
    final style = results[6] as String;
    setState(() {
      _autoSpeak     = results[0] as bool;
      _fontSize      = results[1] as double;
      _lineHeight    = results[2] as double;
      _theme         = results[3] as String;
      _fontFamily    = results[4] as String;
      _margin        = results[5] as double;
      _pageTurnStyle = style;
      _autoTranslate = results[8] as bool;
      // Invalidate swipe page cache so it's recomputed with new settings
      _swipePagesForHeight = -1;
    });
    // Restore scroll position in continuous scroll mode.
    if (style == PageTurnStyle.scroll) {
      final offset = results[7] as double;
      if (offset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(
                offset.clamp(0.0, _scroll.position.maxScrollExtent));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _scrollSaveTimer?.cancel();
    _scroll.removeListener(_onScrolled);
    _scroll.dispose();
    _pageCtrl.dispose();
    _saveProgress();
    super.dispose();
  }

  void _clearAllSelections() {
    for (final k in _paraKeys.values) {
      k.currentState?.clearSelection();
    }
    _selectedParaIdx = -1;
  }

  Future<void> _refreshVocab() async {
    final set = await DatabaseService.getVocabWordSet();
    final map = await DatabaseService.getVocabWordDefMap();
    if (mounted) setState(() { _vocabSet = set; _vocabDefMap = map; });
  }

  Future<void> _refreshBookmarksAndNotes() async {
    final bookId = widget.book.id;
    if (bookId == null) return;
    final bm = await DatabaseService.getBookmarks(bookId);
    final notes = await DatabaseService.getReaderNotes(bookId);
    if (mounted) setState(() { _bookmarks = bm; _readerNotes = notes; });
  }

  Future<void> _addBookmark() async {
    final bookId = widget.book.id;
    if (bookId == null) return;
    final paras = BookParser.getPage(widget.paragraphs, _page);
    final snippet = paras.isNotEmpty
        ? paras.first.substring(0, paras.first.length.clamp(0, 80))
        : 'Page ${_page + 1}';
    await DatabaseService.addBookmark(Bookmark(
      bookId: bookId, page: _page,
      snippet: snippet, createdAt: DateTime.now(),
    ));
    await _refreshBookmarksAndNotes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('书签已添加'),
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  Future<void> _refreshSources() async {
    final all = await DatabaseService.getAllDictSources();
    if (mounted) setState(() => _activeSources = all.where((s) => s.enabled).toList());
  }

  void _onScrolled() {
    if (_pageTurnStyle != PageTurnStyle.scroll) return;
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (widget.book.id != null && _scroll.hasClients) {
        SettingsService.setScrollOffset(widget.book.id!, _scroll.offset);
      }
    });
  }

  Future<void> _saveProgress() async {
    if (widget.book.id == null) return;
    await DatabaseService.updateBookProgress(widget.book.id!, _page, _totalPages);
    if (_pageTurnStyle == PageTurnStyle.scroll && _scroll.hasClients) {
      await SettingsService.setScrollOffset(widget.book.id!, _scroll.offset);
    }
  }

  void _goPage(int delta) {
    final next = _page + delta;
    if (next < 0 || next >= _totalPages) return;
    _removeOverlay();
    _paraKeys.clear();
    if (_pageTurnStyle == PageTurnStyle.swipe) {
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      // _page updated in onPageChanged
    } else {
      setState(() => _page = next);
      _scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      _saveProgress();
    }
  }

  void _toggleAutoSpeak() {
    final v = !_autoSpeak;
    setState(() => _autoSpeak = v);
    SettingsService.setAutoSpeak(v);
    if (v) TtsService.speak('auto');
  }

  // ── Word lookup overlay ────────────────────────────────────────────────────

  Future<void> _onWordTap(String word, String paraText, int paraIdx) async {
    final sentence = BookParser.extractSentence(paraText, word);
    final hitKey = '${word}_${DateTime.now().millisecondsSinceEpoch}';

    // Clear previous paragraph's selection if different paragraph
    if (_selectedParaIdx >= 0 && _selectedParaIdx != paraIdx) {
      _paraKeys[_selectedParaIdx]?.currentState?.clearSelection();
    }
    _selectedParaIdx = paraIdx;

    _removeOverlayOnly();
    _overlayHitKey = hitKey;
    _overlayResult = null;
    _overlayLoading = true;
    _showWordOverlay(word, sentence);

    if (_autoSpeak) TtsService.speak(word);

    final result = await DictionaryService.lookup(word);
    if (!mounted || _overlayHitKey != hitKey) return;
    _overlayResult = result;
    _overlayLoading = false;
    _overlayEntry?.markNeedsBuild();
  }

  void _showWordOverlay(String word, String sentence) {
    final size = MediaQuery.of(context).size;
    const cardW = 320.0;

    _overlayEntry = OverlayEntry(builder: (ctx) {
      double left = _tapPos.dx - cardW / 2;
      left = left.clamp(8.0, size.width - cardW - 8.0);
      final topPad = MediaQuery.of(ctx).padding.top;
      final botPad = MediaQuery.of(ctx).padding.bottom;
      // Estimate max card height: tab list (36% screen) + header + toolbar + tabs + padding
      final estCardH = size.height * 0.36 + 200.0;
      final spaceAbove = _tapPos.dy - 24 - topPad - 8;
      final spaceBelow = size.height - botPad - 8 - (_tapPos.dy + 32);
      double top;
      if (spaceAbove >= spaceBelow) {
        // More room above — show card above tap, clamp so it doesn't go above status bar
        top = (_tapPos.dy - 24 - estCardH).clamp(topPad + 8, size.height);
      } else {
        // More room below — show card below tap, clamp so it doesn't go off screen
        top = (_tapPos.dy + 32).clamp(topPad + 8, size.height - botPad - estCardH - 8);
      }

      return Stack(children: [
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _removeOverlay,
          child: const SizedBox.expand(),
        )),
        Positioned(
          left: left, top: top, width: cardW,
          child: FloatingWordCard(
            result: _overlayResult,
            loading: _overlayLoading,
            word: word,
            sentence: sentence,
            bookTitle: widget.book.title,
            savedDefinitionText: _vocabDefMap[word.toLowerCase()],
            allSources: _activeSources,
            onStar: (def) => _starDefinition(word, sentence, def, _overlayResult?.phonetic ?? ''),
            onUnstar: () => _unstar(word),
            onDismiss: _removeOverlay,
            onEdit: () => _editVocabEntry(word),
            onToolbarAction: (action, w) => _onWordToolbarAction(action, w),
          ),
        ),
      ]);
    });
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ── Sentence translate overlay ─────────────────────────────────────────────

  void _showTranslateOverlay(String text, {String paraText = ''}) {
    if (text.trim().isEmpty) return;
    _removeOverlayOnly(); // don't clear paragraph selections
    _translateText = text.trim();
    _translateParaText = paraText;
    // Reset per-engine starred state for new text
    _translateStarredEngines = {};

    final size = MediaQuery.of(context).size;
    const cardW = 320.0;

    _overlayEntry = OverlayEntry(builder: (ctx) {
      double left = _tapPos.dx - cardW / 2;
      left = left.clamp(8.0, size.width - cardW - 8.0);
      final topPad = MediaQuery.of(ctx).padding.top;
      final botPad = MediaQuery.of(ctx).padding.bottom;
      // Card limits itself to 75% of usable screen height
      final estCardH = (size.height - topPad - botPad) * 0.75;
      final spaceAbove = _tapPos.dy - 24 - topPad - 8;
      final spaceBelow = size.height - botPad - 8 - (_tapPos.dy + 32);
      double top;
      if (spaceAbove >= spaceBelow) {
        top = (_tapPos.dy - 24 - estCardH).clamp(topPad + 8, size.height);
      } else {
        top = (_tapPos.dy + 32).clamp(topPad + 8, size.height - botPad - estCardH - 8);
      }

      return Stack(children: [
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _removeOverlay,
          child: const SizedBox.expand(),
        )),
        Positioned(
          left: left, top: top, width: cardW,
          child: FloatingTranslateCard(
            originalText: _translateText,
            onDismiss: _removeOverlay,
            onToolbarAction: (action, text) =>
                _onSelectionAction(_selectionActionFromString(action), text),
            starredEngineIds: _translateStarredEngines,
            onStar: (phrase, translation, engineId) =>
                _starPhrase(phrase, translation, engineId),
            onUnstar: (engineId) => _unstarTranslate(_translateText, engineId),
            onEdit: (engineId, translation) =>
                _editTranslateEntry(_translateText, translation),
            autoSpeak: _autoSpeak,
          ),
        ),
      ]);
    });
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlayOnly() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _removeOverlay() {
    _removeOverlayOnly();
    _clearAllSelections();
  }

  // ── Star / unstar ──────────────────────────────────────────────────────────

  Future<void> _starDefinition(String word, String sentence, Definition def, [String phonetic = '']) async {
    // Prefer per-definition Chinese, then cached word-level Google Translate.
    // If neither is ready, fetch now (background fetch may not have completed yet).
    String cn = def.chineseText.isNotEmpty ? def.chineseText : '';
    if (cn.isEmpty) {
      final cached = await DatabaseService.getChineseCached(word.toLowerCase());
      cn = (cached != null && cached.isNotEmpty)
          ? cached
          : await DictionaryService.translateSentence(word);
    }
    await DatabaseService.addOrUpdateWord(VocabEntry(
      word: word, phonetic: phonetic,
      definition: def.text, chineseMeaning: cn,
      partOfSpeech: def.partOfSpeech,
      sentence: sentence, source: widget.book.title,
    ));
    await _refreshVocab();
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _unstar(String word) async {
    await DatabaseService.deleteWordByName(word);
    await _refreshVocab();
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _starPhrase(String phrase, String translation, String engineId) async {
    // If the selected text itself ends with sentence punctuation it IS the sentence.
    // Otherwise extract the containing sentence from the paragraph.
    final endsWithPunct = RegExp(r'[.!?]$').hasMatch(phrase.trim());
    final sentence = endsWithPunct
        ? phrase.trim()
        : (_translateParaText.isNotEmpty
            ? BookParser.extractSentence(_translateParaText, phrase)
            : '');
    await DatabaseService.addOrUpdateWord(VocabEntry(
      word: phrase,
      definition: '',
      chineseMeaning: translation,
      sentence: sentence,
      source: widget.book.title,
    ));
    setState(() => _translateStarredEngines = {..._translateStarredEngines, engineId});
    await _refreshVocab();
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _unstarTranslate(String phrase, String engineId) async {
    await DatabaseService.deleteWordByName(phrase);
    setState(() {
      _translateStarredEngines = {..._translateStarredEngines}..remove(engineId);
    });
    await _refreshVocab();
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _editTranslateEntry(String phrase, String translation) async {
    final allWords = await DatabaseService.getAllWords();
    final entry = allWords.firstWhere(
      (e) => e.word.toLowerCase() == phrase.toLowerCase(),
      orElse: () => VocabEntry(word: phrase, definition: '', chineseMeaning: translation, sentence: ''),
    );

    final phoneticCtrl = TextEditingController(text: entry.phonetic);
    final posCtrl      = TextEditingController(text: entry.partOfSpeech);
    final defCtrl      = TextEditingController(text: entry.definition);
    final cnCtrl       = TextEditingController(text: entry.chineseMeaning.isNotEmpty ? entry.chineseMeaning : translation);
    final sentCtrl     = TextEditingController(text: entry.sentence);

    if (!mounted) return;
    _removeOverlayOnly();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditVocabSheet(
          word: phrase,
          phoneticCtrl: phoneticCtrl,
          posCtrl: posCtrl,
          defCtrl: defCtrl,
          cnCtrl: cnCtrl,
          sentCtrl: sentCtrl,
        ),
      ),
    );

    if (saved == true) {
      await DatabaseService.addOrUpdateWord(VocabEntry(
        id: entry.id,
        word: entry.word,
        phonetic: phoneticCtrl.text.trim(),
        partOfSpeech: posCtrl.text.trim(),
        definition: defCtrl.text.trim(),
        chineseMeaning: cnCtrl.text.trim(),
        sentence: sentCtrl.text.trim(),
        source: entry.source.isNotEmpty ? entry.source : widget.book.title,
        addedAt: entry.addedAt,
      ));
      await _refreshVocab();
      _overlayEntry?.markNeedsBuild();
    }

    phoneticCtrl.dispose();
    posCtrl.dispose();
    defCtrl.dispose();
    cnCtrl.dispose();
    sentCtrl.dispose();
  }

  Future<void> _editVocabEntry(String word) async {
    final allWords = await DatabaseService.getAllWords();
    final entry = allWords.firstWhere(
      (e) => e.word.toLowerCase() == word.toLowerCase(),
      orElse: () => VocabEntry(word: word, definition: '', sentence: ''),
    );

    final phoneticCtrl = TextEditingController(text: entry.phonetic);
    final posCtrl      = TextEditingController(text: entry.partOfSpeech);
    final defCtrl      = TextEditingController(text: entry.definition);
    final cnCtrl       = TextEditingController(text: entry.chineseMeaning);
    final sentCtrl     = TextEditingController(text: entry.sentence);

    if (!mounted) return;
    _removeOverlayOnly();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditVocabSheet(
          word: word,
          phoneticCtrl: phoneticCtrl,
          posCtrl: posCtrl,
          defCtrl: defCtrl,
          cnCtrl: cnCtrl,
          sentCtrl: sentCtrl,
        ),
      ),
    );

    if (saved == true) {
      await DatabaseService.addOrUpdateWord(VocabEntry(
        id: entry.id,
        word: entry.word,
        phonetic: phoneticCtrl.text.trim(),
        partOfSpeech: posCtrl.text.trim(),
        definition: defCtrl.text.trim(),
        chineseMeaning: cnCtrl.text.trim(),
        sentence: sentCtrl.text.trim(),
        source: entry.source,
        addedAt: entry.addedAt,
      ));
      await _refreshVocab();
      _overlayEntry?.markNeedsBuild();
    }

    phoneticCtrl.dispose();
    posCtrl.dispose();
    defCtrl.dispose();
    cnCtrl.dispose();
    sentCtrl.dispose();
  }

  // ── Word card toolbar actions ──────────────────────────────────────────────

  void _onWordToolbarAction(String action, String word) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: word));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
      case 'highlight':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('划线功能即将上线'), duration: Duration(seconds: 1)));
      case 'note':
        _showNoteSheet(word);
      case 'share':
        Clipboard.setData(ClipboardData(text: word));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制，可粘贴分享'), duration: Duration(seconds: 1)));
    }
  }

  // ── Selection toolbar actions ──────────────────────────────────────────────

  _SelectionAction _selectionActionFromString(String s) {
    switch (s) {
      case 'copy': return _SelectionAction.copy;
      case 'search': return _SelectionAction.search;
      case 'highlight': return _SelectionAction.highlight;
      case 'note': return _SelectionAction.note;
      default: return _SelectionAction.share;
    }
  }

  void _onSelectionAction(_SelectionAction action, String text) {
    switch (action) {
      case _SelectionAction.copy:
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
        );
      case _SelectionAction.search:
        // Single word → word card already open; multi-word → translate overlay
        _showTranslateOverlay(text);
      case _SelectionAction.highlight:
        // TODO: persist highlight ranges
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('划线功能即将上线'), duration: Duration(seconds: 1)),
        );
      case _SelectionAction.note:
        _showNoteSheet(text);
      case _SelectionAction.share:
        // Use system share sheet via Clipboard for now
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制，可粘贴分享'), duration: Duration(seconds: 1)),
        );
    }
  }

  void _showNoteSheet(String selectedText) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('笔记', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
              child: Text(selectedText, style: const TextStyle(fontSize: 13, color: Color(0xFF666666), height: 1.5)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4, minLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '写下你的笔记...',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFFDDDDDD))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFFDDDDDD))),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true, fillColor: Color(0xFFF8F8F8),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final bookId = widget.book.id;
                  if (bookId != null && ctrl.text.trim().isNotEmpty) {
                    await DatabaseService.addReaderNote(ReaderNote(
                      bookId: bookId, page: _page,
                      selectedText: selectedText,
                      noteText: ctrl.text.trim(),
                      createdAt: DateTime.now(),
                    ));
                    await _refreshBookmarksAndNotes();
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('笔记已保存'), duration: Duration(seconds: 1)));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0),
                child: const Text('保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              )),
          ]),
        ),
      ),
    );
  }

  // ── Search panel ─────────────────────────────────────────────────────────

  void _showSearchPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchPanel(
        paragraphs: widget.paragraphs,
        onJumpToPage: (page) {
          Navigator.pop(ctx);
          _goToPage(page);
        },
      ),
    );
  }

  // ── TOC panel ────────────────────────────────────────────────────────────

  List<({int paraIdx, int page, String title})> _buildToc() {
    final result = <({int paraIdx, int page, String title})>[];
    final chapterRe = RegExp(
      r'^(chapter|part|section|prologue|epilogue|introduction|preface|afterword|appendix|act\s)',
      caseSensitive: false,
    );
    for (var i = 0; i < widget.paragraphs.length; i++) {
      final t = widget.paragraphs[i].trim();
      if (t.isEmpty || t.length > 100) continue;
      final isChapter = chapterRe.hasMatch(t);
      final isAllCaps = t == t.toUpperCase() && t.length >= 3 && RegExp(r'[A-Z]').hasMatch(t);
      if (isChapter || isAllCaps) {
        result.add((paraIdx: i, page: i ~/ BookParser.perPage, title: t));
      }
    }
    return result;
  }

  void _showTocPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TocPanel(
        toc: _buildToc(),
        bookmarks: _bookmarks,
        notes: _readerNotes,
        currentPage: _page,
        totalPages: _totalPages,
        onJumpToPage: (page) {
          Navigator.pop(ctx);
          _goToPage(page);
        },
        onDeleteBookmark: (id) async {
          await DatabaseService.deleteBookmark(id);
          await _refreshBookmarksAndNotes();
          if (ctx.mounted) Navigator.pop(ctx);
          _showTocPanel();
        },
        onDeleteNote: (id) async {
          await DatabaseService.deleteReaderNote(id);
          await _refreshBookmarksAndNotes();
          if (ctx.mounted) Navigator.pop(ctx);
          _showTocPanel();
        },
      ),
    );
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _totalPages - 1);
    _removeOverlay();
    _paraKeys.clear();
    if (_pageTurnStyle == PageTurnStyle.swipe) {
      _pageCtrl.animateToPage(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      setState(() => _page = target);
      _scroll.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      _saveProgress();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTheme.primary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(children: [
          Text(widget.book.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          Text('Page ${_page + 1} of $_totalPages',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          IconButton(
            icon: Icon(_autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 22),
            color: _autoSpeak ? AppTheme.primary : AppTheme.textTertiary,
            tooltip: _autoSpeak ? '自动发音：开' : '自动发音：关',
            onPressed: _toggleAutoSpeak,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            color: AppTheme.primary,
            tooltip: '全文搜索',
            onPressed: _showSearchPanel,
          ),
          IconButton(
            icon: const Icon(Icons.menu_book_rounded, size: 22),
            color: AppTheme.primary,
            tooltip: '目录/书签/笔记',
            onPressed: _showTocPanel,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 22),
            color: AppTheme.primary,
            tooltip: '设置',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _loadSettings();
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 700) _addBookmark();        // 下拉 → 书签
          else if (v < -700) Navigator.of(context).pop(); // 上拉 → 关闭
        },
        child: _pageTurnStyle == PageTurnStyle.swipe
            ? _buildSwipeContent()
            : _buildScrollContent(),
      ),
    );
  }

  // ── Scroll mode ───────────────────────────────────────────────────────────
  // Group every 8 original paragraphs into one TextField so selection can
  // span multiple sentences (original blank-line-separated chunks).
  static const _scrollGroupSize = 8;

  Widget _buildScrollContent() {
    final total = widget.paragraphs.length;
    final groupCount = (total + _scrollGroupSize - 1) ~/ _scrollGroupSize;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.symmetric(horizontal: _margin, vertical: 20),
      itemCount: groupCount,
      itemBuilder: (ctx, groupIdx) {
        final start = groupIdx * _scrollGroupSize;
        final end = (start + _scrollGroupSize).clamp(0, total);
        final text = widget.paragraphs.sublist(start, end).join('\n\n');
        final key = _paraKeys.putIfAbsent(
            start, () => GlobalKey<_ReaderParagraphState>());
        return _buildParaWidget(key: key, text: text, paraKey: start);
      },
    );
  }

  // ── Swipe mode ────────────────────────────────────────────────────────────
  Widget _buildSwipeContent() {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    const topPad = 20.0;
    final bottomPad = 16.0 + bottomInset;

    return LayoutBuilder(builder: (ctx, constraints) {
      final pageWidth  = constraints.maxWidth  - _margin * 2;
      final pageHeight = constraints.maxHeight - topPad - bottomPad;

      // Schedule rebuild if size or font settings changed.
      _maybeRebuildSwipePages(pageHeight, pageWidth);

      if (_swipePages.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      return PageView.builder(
        controller: _pageCtrl,
        itemCount: _totalPages,
        onPageChanged: (idx) {
          _removeOverlay();
          _paraKeys.clear();
          setState(() => _page = idx);
          _saveProgress();
        },
        itemBuilder: (ctx, pageIdx) {
          if (pageIdx >= _swipePages.length) return const SizedBox.shrink();
          final paras = _swipePages[pageIdx];
          return Padding(
            padding: EdgeInsets.fromLTRB(_margin, topPad, _margin, bottomPad),
            child: _buildParaWidget(
              key: _paraKeys.putIfAbsent(
                  pageIdx * 10000,
                  () => GlobalKey<_ReaderParagraphState>()),
              text: paras.join('\n\n'),
              paraKey: pageIdx * 10000,
            ),
          );
        },
      );
    });
  }

  // ── Shared paragraph builder ──────────────────────────────────────────────
  Widget _buildParaWidget({
    required GlobalKey<_ReaderParagraphState> key,
    required String text,
    required int paraKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: _ReaderParagraph(
        key: key,
        text: text,
        vocabSet: _vocabSet,
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        textColor: _textColor,
        fontFamily: _fontFamily,
        autoTranslate: _autoTranslate,
        onWordTap: (word, globalPos) {
          _tapPos = globalPos;
          _onWordTap(word, text, paraKey);
        },
        onTranslate: (selectedText, globalPos) {
          _tapPos = globalPos;
          _showTranslateOverlay(selectedText, paraText: text);
        },
        onSelectionAction: (action, selectedText) =>
            _onSelectionAction(action, selectedText),
        onTapOutside: () {},
      ),
    );
  }
}

// ── Custom controller that renders vocab underlines ────────────────────────────

class _VocabTextController extends TextEditingController {
  Set<String> vocabSet;
  Color textColor;
  static final _wordRe = RegExp(r"\b[a-zA-Z]+(?:'[a-zA-Z]+)?\b");
  static const _hlColor = Color(0x55D4A017);

  _VocabTextController({
    required String text,
    required this.vocabSet,
    required this.textColor,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final lower = text.toLowerCase();

    // 1. Find all phrase (multi-word) highlight ranges first.
    //    A phrase entry contains a space; single-word entries are handled per-word below.
    final phraseRanges = <(int, int)>[];
    for (final entry in vocabSet) {
      if (!entry.contains(' ')) continue; // single words handled separately
      var searchFrom = 0;
      while (true) {
        final idx = lower.indexOf(entry, searchFrom);
        if (idx < 0) break;
        phraseRanges.add((idx, idx + entry.length));
        searchFrom = idx + entry.length;
      }
    }

    // Helper: is position [pos] inside any phrase range?
    bool inPhrase(int pos) =>
        phraseRanges.any((r) => pos >= r.$1 && pos < r.$2);

    final spans = <InlineSpan>[];
    var last = 0;

    // 2. Merge phrase ranges and word ranges into a unified span list.
    //    Sort phrase ranges by start position, then walk through the text.
    phraseRanges.sort((a, b) => a.$1.compareTo(b.$1));

    // Collect word matches that are NOT inside a phrase range.
    final wordMatches = _wordRe.allMatches(text)
        .where((m) => !phraseRanges.any((r) => m.start >= r.$1 && m.end <= r.$2))
        .toList();

    // Build a combined list of (start, end, isPhrase) events.
    final events = <(int, int, bool)>[
      for (final r in phraseRanges) (r.$1, r.$2, true),
      for (final m in wordMatches) (m.start, m.end, false),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (start, end, isPhrase) in events) {
      if (start < last) continue; // overlapping — skip
      if (start > last) {
        spans.add(TextSpan(text: text.substring(last, start), style: base));
      }
      final chunk = text.substring(start, end);
      final highlighted = isPhrase
          ? true
          : vocabSet.contains(chunk.toLowerCase());
      spans.add(TextSpan(
        text: chunk,
        style: base.copyWith(
          decoration: TextDecoration.none,
          backgroundColor: highlighted ? _hlColor : null,
        ),
      ));
      last = end;
    }

    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return TextSpan(children: spans);
  }
}

// ── Reader paragraph: TextField(readOnly) with native selection handles ────────

enum _SelectionAction { copy, search, highlight, note, share }

class _ReaderParagraph extends StatefulWidget {
  final String text;
  final Set<String> vocabSet;
  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final String fontFamily;
  final bool autoTranslate;
  final void Function(String word, Offset globalPos) onWordTap;
  final void Function(String selectedText, Offset globalPos) onTranslate;
  final void Function(_SelectionAction action, String selectedText) onSelectionAction;
  final VoidCallback onTapOutside;

  const _ReaderParagraph({
    super.key,
    required this.text,
    required this.vocabSet,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.fontFamily,
    this.autoTranslate = true,
    required this.onWordTap,
    required this.onTranslate,
    required this.onSelectionAction,
    required this.onTapOutside,
  });

  @override
  State<_ReaderParagraph> createState() => _ReaderParagraphState();
}

class _ReaderParagraphState extends State<_ReaderParagraph> {
  late final _VocabTextController _ctrl;
  final _focusNode = FocusNode();
  late List<(int, int)> _wordRanges;
  Timer? _translateTimer;
  Timer? _suppressOutsideTimer;
  Timer? _longPressTimer;
  Timer? _wordTapTimer;
  Offset? _longPressDownPos;
  bool _suppressListener = false;
  bool _suppressOutside = false;
  bool _isDragging = false;
  // Double-tap detection
  DateTime? _lastTapTime;
  Offset?   _lastTapPos;
  bool _suppressNextTap = false;
  @override
  void initState() {
    super.initState();
    _wordRanges = _buildWordRanges(widget.text);
    _ctrl = _buildController();
    _ctrl.addListener(_onSelectionChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (event is PointerUpEvent) {
      // Finger lifted anywhere on screen — if there's a pending translate timer
      // and selection is non-collapsed, fire immediately instead of waiting.
      if (_translateTimer?.isActive == true) {
        _translateTimer!.cancel();
        _translateTimer = null;
        final sel = _ctrl.selection;
        if (!sel.isCollapsed && sel.start >= 0) {
          final selected = widget.text.substring(sel.start, sel.end).trim();
          if (selected.isNotEmpty && widget.autoTranslate && !_suppressListener) {
            _suppressOutside = true;
            _suppressOutsideTimer?.cancel();
            _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
              _suppressOutside = false;
            });
            final anchor = _getSelectionAnchor();
            widget.onTranslate(selected, anchor);
          }
        }
      }
    }
  }

  void _onSelectionChanged() {
    final sel = _ctrl.selection;
    if (sel.isCollapsed || sel.start < 0) return;
    final selected = widget.text.substring(sel.start, sel.end).trim();
    if (selected.isEmpty) return;

    if (_suppressListener) return; // programmatic single-word tap — no toolbar
    if (_isDragging) return; // user is dragging selection handles — wait for release

    // Single exact word → already handled by onTap
    final isExactWord = _wordRanges.any((r) => r.$1 == sel.start && r.$2 == sel.end);
    if (isExactWord) return;

    // Multi-word: debounce 2000ms so dragging selection handles doesn't trigger translate
    if (!widget.autoTranslate) return;
    _translateTimer?.cancel();
    _translateTimer = Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      _suppressOutside = true;
      _suppressOutsideTimer?.cancel();
      _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
        _suppressOutside = false;
      });
      final anchor = _getSelectionAnchor();
      widget.onTranslate(selected, anchor);
    });
  }

  Offset _getSelectionAnchor() {
    try {
      final ro = context.findRenderObject();
      RenderEditable? re;
      void visit(RenderObject o) {
        if (o is RenderEditable) { re = o; return; }
        o.visitChildren(visit);
      }
      if (ro != null) visit(ro);
      if (re == null) return Offset.zero;
      final sel = _ctrl.selection;
      final boxes = re!.getBoxesForSelection(sel);
      if (boxes.isNotEmpty) {
        final b = boxes.first;
        return re!.localToGlobal(Offset(b.left, b.top));
      }
    } catch (_) {}
    return Offset.zero;
  }

  @override
  void didUpdateWidget(_ReaderParagraph old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.vocabSet != widget.vocabSet ||
        old.textColor != widget.textColor || old.fontSize != widget.fontSize) {
      _wordRanges = _buildWordRanges(widget.text);
      (_ctrl as _VocabTextController)
        ..vocabSet = widget.vocabSet
        ..textColor = widget.textColor;
      setState(() {}); // force TextField to re-invoke buildTextSpan
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    _translateTimer?.cancel();
    _suppressOutsideTimer?.cancel();
    _longPressTimer?.cancel();
    _wordTapTimer?.cancel();
    _ctrl.removeListener(_onSelectionChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static List<(int, int)> _buildWordRanges(String text) {
    final re = RegExp(r"\b[a-zA-Z]+(?:'[a-zA-Z]+)?\b");
    return re.allMatches(text).map((m) => (m.start, m.end)).toList();
  }

  _VocabTextController _buildController() {
    return _VocabTextController(
      text: widget.text,
      vocabSet: widget.vocabSet,
      textColor: widget.textColor,
    );
  }

  void clearSelection() {
    if (_ctrl.selection.start != -1) {
      _ctrl.selection = const TextSelection.collapsed(offset: -1);
    }
    if (_focusNode.hasFocus) _focusNode.unfocus();
  }

  /// Returns the [start, end) char range of the sentence containing [charOffset].
  static (int, int) _sentenceBoundsAt(String text, int charOffset) {
    final boundaries = <int>[0];
    final re = RegExp(r'[.!?]+(?:\s|$)');
    for (final m in re.allMatches(text)) {
      boundaries.add(m.end);
    }
    boundaries.add(text.length);

    for (int i = 0; i < boundaries.length - 1; i++) {
      final s = boundaries[i];
      final e = boundaries[i + 1];
      if (charOffset >= s && charOffset < e) {
        // skip leading whitespace AND newlines (present in merged paragraphs)
        var trimS = s;
        while (trimS < e && text[trimS].trim().isEmpty) trimS++;
        return (trimS, e);
      }
    }
    return (0, text.length);
  }

  /// Double-tap: select and translate the sentence at [charOffset].
  void _handleSentenceTap(int charOffset) {
    if (charOffset < 0 || charOffset >= widget.text.length) return;
    final (s, e) = _sentenceBoundsAt(widget.text, charOffset);
    final sentence = widget.text.substring(s, e).trim();
    if (sentence.isEmpty) return;
    _suppressListener = true;
    _ctrl.selection = TextSelection(baseOffset: s, extentOffset: e);
    _suppressOutside = true;
    _suppressOutsideTimer?.cancel();
    _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
      _suppressOutside = false;
      _suppressListener = false;
    });
    final anchor = _getSelectionAnchor();
    widget.onTranslate(sentence, anchor);
  }

  /// Long-press on word: show word lookup card.
  /// Only fires when the offset is inside a highlighted multi-word phrase/sentence.
  void _handleLongPress(int offset) {
    if (offset < 0) return;

    // Guard: long-press lookup only works inside highlighted phrases/sentences.
    // Single-word vocab entries and plain text use single-tap for lookup.
    final lower = widget.text.toLowerCase();
    bool insidePhrase = false;
    for (final entry in widget.vocabSet) {
      if (!entry.contains(' ')) continue; // single-word entries: no long-press
      var from = 0;
      while (true) {
        final idx = lower.indexOf(entry, from);
        if (idx < 0) break;
        final end = idx + entry.length;
        if (offset >= idx && offset < end) { insidePhrase = true; break; }
        from = end;
      }
      if (insidePhrase) break;
    }
    if (!insidePhrase) return;

    // Find which word range contains this offset.
    for (final (start, end) in _wordRanges) {
      if (offset >= start && offset <= end) {
        final word = widget.text.substring(start, end);
        _suppressListener = true;
        _ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
        // Keep _suppressListener = true until timer fires — prevents any
        // selection changes from TextField's internal long-press handling
        // from starting the translate timer.
        final anchor = _getSelectionAnchor();
        _suppressOutside = true;
        _suppressOutsideTimer?.cancel();
        _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
          _suppressOutside = false;
          _suppressListener = false;
        });
        widget.onWordTap(word, anchor);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listener sits outside the gesture arena — always receives pointer events
    // regardless of what the TextField's internal recognizers do.
    // We implement long-press detection here so it fires even inside highlighted
    // phrases where the TextField's own LongPressGestureRecognizer would win.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // ── Double-tap detection ─────────────────────────────────────────────
        final now = DateTime.now();
        final pos = event.position;
        if (_lastTapTime != null && _lastTapPos != null) {
          final dt = now.difference(_lastTapTime!).inMilliseconds;
          final dist = (pos - _lastTapPos!).distance;
          if (dt < 300 && dist < 40) {
            // Double-tap: translate sentence at cursor position
            _lastTapTime = null;
            _lastTapPos = null;
            _suppressNextTap = true; // prevent onTap word-lookup on this tap
            _wordTapTimer?.cancel();  // cancel any pending word-lookup from first tap
            _longPressTimer?.cancel();
            _translateTimer?.cancel();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final offset = _ctrl.selection.baseOffset;
              _handleSentenceTap(offset);
            });
            return;
          }
        }
        _lastTapTime = now;
        _lastTapPos = pos;
        // ── Long-press detection ─────────────────────────────────────────────
        _longPressTimer?.cancel();
        _longPressDownPos = event.position;
        _longPressTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _longPressDownPos == null) return;
          _translateTimer?.cancel();
          // Read cursor offset inside the timer (500 ms after pointer-down):
          // by this time TextField has positioned the cursor at the tapped
          // character, so baseOffset reflects the actual finger position.
          final offset = _ctrl.selection.baseOffset;
          if (offset >= 0) _handleLongPress(offset);
        });
      },
      onPointerUp: (_) {
        _longPressTimer?.cancel();
        _longPressDownPos = null;
        if (_isDragging) {
          _isDragging = false;
          // Trigger translate after drag ends
          _onSelectionChanged();
        }
      },
      onPointerCancel: (_) {
        _longPressTimer?.cancel();
        _longPressDownPos = null;
        _isDragging = false;
      },
      onPointerMove: (event) {
        // Cancel long-press only when finger drifts >10 px from touch-down.
        if (_longPressDownPos != null) {
          if ((event.position - _longPressDownPos!).distance > 10) {
            _longPressTimer?.cancel();
            _longPressDownPos = null;
          }
        }
        _isDragging = true;
      },
      child: TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          readOnly: true,
          maxLines: null,
          enableInteractiveSelection: true,
          style: TextStyle(
            fontSize: widget.fontSize,
            height: widget.lineHeight,
            color: widget.textColor,
            fontFamily: widget.fontFamily,
            letterSpacing: 0.15,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          contextMenuBuilder: (ctx, editableState) => const SizedBox.shrink(),
          onTapAlwaysCalled: true,
          onTap: () {
            // Double-tap fires onTap for its second press — skip word lookup.
            if (_suppressNextTap) { _suppressNextTap = false; return; }
            final offset = _ctrl.selection.baseOffset;
            if (offset < 0) return;

            // Delay word/phrase lookup to allow double-tap cancellation.
            // Must be > double-tap detection window (300 ms) to ensure the
            // second pointerDown arrives in time to cancel this timer.
            _wordTapTimer?.cancel();
            _wordTapTimer = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;

              // ── Priority 1: highlighted PHRASE (multi-word) → translate overlay ────
              final lower = widget.text.toLowerCase();
              for (final entry in widget.vocabSet) {
                if (!entry.contains(' ')) continue;
                var searchFrom = 0;
                while (true) {
                  final idx = lower.indexOf(entry, searchFrom);
                  if (idx < 0) break;
                  final end = idx + entry.length;
                  if (offset >= idx && offset < end) {
                    final phrase = widget.text.substring(idx, end);
                    _suppressListener = true;
                    _ctrl.selection = TextSelection(baseOffset: idx, extentOffset: end);
                    _suppressListener = false;
                    final anchor = _getSelectionAnchor();
                    _suppressOutside = true;
                    _suppressOutsideTimer?.cancel();
                    _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
                      _suppressOutside = false;
                    });
                    widget.onTranslate(phrase, anchor);
                    return;
                  }
                  searchFrom = idx + entry.length;
                }
              }

              // ── Priority 2: any word (highlighted or not) → word lookup card ────────
              for (final (start, end) in _wordRanges) {
                if (offset >= start && offset <= end) {
                  final word = widget.text.substring(start, end);
                  _suppressListener = true;
                  _ctrl.selection = TextSelection(baseOffset: start, extentOffset: end);
                  _suppressListener = false;
                  final anchor = _getSelectionAnchor();
                  _suppressOutside = true;
                  _suppressOutsideTimer?.cancel();
                  _suppressOutsideTimer = Timer(const Duration(milliseconds: 600), () {
                    _suppressOutside = false;
                  });
                  widget.onWordTap(word, anchor);
                  return;
                }
              }
              // Punctuation / non-word: do nothing.
            });
          },
          onTapOutside: (_) {
            if (_suppressOutside) return;
            widget.onTapOutside();
          },
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int page;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PaginationBar({required this.page, required this.total, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.readerBg,
        border: Border(top: BorderSide(color: AppTheme.separator.withValues(alpha: 0.6))),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavBtn(icon: Icons.chevron_left_rounded, label: 'Prev', onTap: onPrev),
          Text('${page + 1} / $total',
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
          _NavBtn(icon: Icons.chevron_right_rounded, label: 'Next', trailingIcon: true, onTap: onNext),
        ],
      ),
    );
  }
}

// ── Edit vocab bottom sheet ───────────────────────────────────────────────────

class _EditVocabSheet extends StatelessWidget {
  final String word;
  final TextEditingController phoneticCtrl;
  final TextEditingController posCtrl;
  final TextEditingController defCtrl;
  final TextEditingController cnCtrl;
  final TextEditingController sentCtrl;

  const _EditVocabSheet({
    required this.word,
    required this.phoneticCtrl,
    required this.posCtrl,
    required this.defCtrl,
    required this.cnCtrl,
    required this.sentCtrl,
  });

  @override
  Widget build(BuildContext context) {
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
          // ── Handle + title ───────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(children: [
            Text(word,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context, false),
              child: const Icon(Icons.close_rounded,
                  color: AppTheme.textTertiary),
            ),
          ]),
          const SizedBox(height: 18),
          // ── 音标 ─────────────────────────────────────────────────────────
          const Text('音标',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: phoneticCtrl,
            maxLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Color(0xFFF8F8F8),
              hintText: '如 /wɜːrd/',
            ),
          ),
          const SizedBox(height: 14),
          // ── 词性 ─────────────────────────────────────────────────────────
          const Text('词性',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: posCtrl,
            maxLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Color(0xFFF8F8F8),
              hintText: '如 noun / verb / adj',
            ),
          ),
          const SizedBox(height: 14),
          // ── 定义（英文）───────────────────────────────────────────────────
          const Text('定义',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: defCtrl,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Color(0xFFF8F8F8),
              hintText: '英文解释',
            ),
          ),
          const SizedBox(height: 14),
          // ── 翻译（中文）───────────────────────────────────────────────────
          const Text('翻译',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: cnCtrl,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Color(0xFFF8F8F8),
              hintText: '中文翻译',
            ),
          ),
          const SizedBox(height: 14),
          // ── 例句 ─────────────────────────────────────────────────────────
          const Text('例句',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: sentCtrl,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFDDDDDD))),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Color(0xFFF8F8F8),
            ),
          ),
          const SizedBox(height: 20),
          // ── 保存 ─────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('保存',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
       ),
      ),
    );
  }
}

// ── TOC / Bookmarks / Notes panel ────────────────────────────────────────────

class _TocPanel extends StatefulWidget {
  final List<({int paraIdx, int page, String title})> toc;
  final List<Bookmark> bookmarks;
  final List<ReaderNote> notes;
  final int currentPage;
  final int totalPages;
  final void Function(int page) onJumpToPage;
  final void Function(int id) onDeleteBookmark;
  final void Function(int id) onDeleteNote;

  const _TocPanel({
    required this.toc,
    required this.bookmarks,
    required this.notes,
    required this.currentPage,
    required this.totalPages,
    required this.onJumpToPage,
    required this.onDeleteBookmark,
    required this.onDeleteNote,
  });

  @override
  State<_TocPanel> createState() => _TocPanelState();
}

class _TocPanelState extends State<_TocPanel> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Tab bar
        TabBar(
          controller: _tab,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '目录'),
            Tab(text: '书签'),
            Tab(text: '笔记'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildTocTab(),
              _buildBookmarksTab(),
              _buildNotesTab(),
            ],
          ),
        ),
        SizedBox(height: bottom),
      ]),
    );
  }

  Widget _buildTocTab() {
    if (widget.toc.isEmpty) {
      return const Center(
        child: Text('未检测到章节目录', style: TextStyle(color: AppTheme.textTertiary)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.toc.length,
      itemBuilder: (_, i) {
        final item = widget.toc[i];
        final isCurrent = item.page == widget.currentPage;
        return ListTile(
          dense: true,
          title: Text(
            item.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
          trailing: Text('第 ${item.page + 1} 页',
              style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
          onTap: () => widget.onJumpToPage(item.page),
        );
      },
    );
  }

  Widget _buildBookmarksTab() {
    if (widget.bookmarks.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bookmark_border_rounded, size: 48, color: AppTheme.textTertiary),
          SizedBox(height: 8),
          Text('下拉添加书签', style: TextStyle(color: AppTheme.textTertiary)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.bookmarks.length,
      itemBuilder: (_, i) {
        final bm = widget.bookmarks[i];
        final isCurrent = bm.page == widget.currentPage;
        return ListTile(
          dense: true,
          leading: Icon(Icons.bookmark_rounded,
              color: isCurrent ? AppTheme.primary : const Color(0xFFFFBB00), size: 20),
          title: Text(
            bm.snippet.isEmpty ? '第 ${bm.page + 1} 页' : bm.snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isCurrent ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
          subtitle: Text('第 ${bm.page + 1} 页',
              style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.textTertiary),
            onPressed: () => widget.onDeleteBookmark(bm.id!),
          ),
          onTap: () => widget.onJumpToPage(bm.page),
        );
      },
    );
  }

  Widget _buildNotesTab() {
    if (widget.notes.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_note_rounded, size: 48, color: AppTheme.textTertiary),
          SizedBox(height: 8),
          Text('长按选中文字可添加笔记', style: TextStyle(color: AppTheme.textTertiary)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.notes.length,
      itemBuilder: (_, i) {
        final note = widget.notes[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('第 ${note.page + 1} 页',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onDeleteNote(note.id!),
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppTheme.textTertiary),
                ),
              ]),
              if (note.selectedText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"${note.selectedText}"',
                  style: const TextStyle(
                    fontSize: 12, color: AppTheme.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Text(note.noteText,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.4)),
              TextButton(
                onPressed: () => widget.onJumpToPage(note.page),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('跳转到此页',
                    style: TextStyle(fontSize: 11, color: AppTheme.primary)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Full-text search panel ────────────────────────────────────────────────────

class _SearchPanel extends StatefulWidget {
  final List<String> paragraphs;
  final void Function(int page) onJumpToPage;

  const _SearchPanel({
    required this.paragraphs,
    required this.onJumpToPage,
  });

  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _ctrl = TextEditingController();
  List<({int page, String snippet})> _results = [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onQueryChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final results = <({int page, String snippet})>[];
    for (var i = 0; i < widget.paragraphs.length; i++) {
      final para = widget.paragraphs[i];
      if (para.toLowerCase().contains(q)) {
        final snippet = BookParser.extractSentence(para, _ctrl.text.trim());
        final page = i ~/ BookParser.perPage;
        results.add((page: page, snippet: snippet));
        if (results.length >= 200) break; // cap results
      }
    }
    setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '搜索书中内容...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary, size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () { _ctrl.clear(); setState(() => _results = []); },
                      child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textTertiary),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F8F8),
            ),
          ),
        ),
        // Result count
        if (_ctrl.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _results.isEmpty ? '未找到结果' : '共 ${_results.length} 处${_results.length >= 200 ? "（已截断）" : ""}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
              ),
            ),
          ),
        const Divider(height: 1),
        // Results list
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _ctrl.text.trim().isEmpty ? '输入关键词开始搜索' : '未找到"${_ctrl.text.trim()}"',
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    return InkWell(
                      onTap: () => widget.onJumpToPage(r.page),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('第 ${r.page + 1} 页',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textTertiary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          _HighlightText(text: r.snippet, query: _ctrl.text.trim()),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        SizedBox(height: bottom),
      ]),
    );
  }
}

/// Renders [text] with all occurrences of [query] highlighted in primary color.
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4));
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    var last = 0;
    var idx = lower.indexOf(lowerQ);
    while (idx >= 0) {
      if (idx > last) {
        spans.add(TextSpan(text: text.substring(last, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0x22007AFF),
        ),
      ));
      last = idx + query.length;
      idx = lower.indexOf(lowerQ, last);
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
        children: spans,
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool trailingIcon;
  final VoidCallback? onTap;

  const _NavBtn({required this.icon, required this.label,
      this.trailingIcon = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap != null ? AppTheme.primary : AppTheme.textTertiary;
    final children = trailingIcon
        ? [Text(label), const SizedBox(width: 2), Icon(icon, size: 22)]
        : [Icon(icon, size: 22), const SizedBox(width: 2), Text(label)];
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: children.map((w) => w is Text
            ? Text(w.data!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color))
            : (w is Icon ? Icon(w.icon, size: w.size, color: color) : w)).toList(),
      ),
    );
  }
}
