import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/vocab_entry.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

class VocabScreen extends StatefulWidget {
  const VocabScreen({super.key});

  @override
  State<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends State<VocabScreen> {
  List<VocabEntry> _entries = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.getAllWords();
    if (mounted) setState(() { _entries = list; _loading = false; });
  }

  Future<void> _delete(VocabEntry e) async {
    await DatabaseService.deleteWord(e.id!);
    setState(() => _entries.remove(e));
  }

  Future<void> _edit(VocabEntry entry) async {
    final phoneticCtrl = TextEditingController(text: entry.phonetic);
    final posCtrl      = TextEditingController(text: entry.partOfSpeech);
    final defCtrl      = TextEditingController(text: entry.definition);
    final cnCtrl       = TextEditingController(text: entry.chineseMeaning);
    final sentCtrl     = TextEditingController(text: entry.sentence);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditSheet(
          word: entry.word,
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
      await _load();
    }

    phoneticCtrl.dispose();
    posCtrl.dispose();
    defCtrl.dispose();
    cnCtrl.dispose();
    sentCtrl.dispose();
  }

  Future<void> _export(String format) async {
    if (_entries.isEmpty) {
      _snack('No words to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final dir  = await getTemporaryDirectory();
      final file = switch (format) {
        'txt_detailed' => await ExportService.exportTxtDetailed(_entries, dir.path),
        'txt_words'    => await ExportService.exportTxtWords   (_entries, dir.path),
        'pdf'          => await ExportService.exportPdf        (_entries, dir.path),
        'apkg'         => await ExportService.exportApkg       (_entries, dir.path),
        _              => throw UnimplementedError(format),
      };
      await Share.shareXFiles([XFile(file.path)], text: 'Vocabulary export');
    } catch (e) {
      if (mounted) _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.groupedBg,
      appBar: AppBar(
        title: Text('Vocabulary (${_entries.length})'),
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTheme.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Column(children: [
            Expanded(child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _buildList()),
            _buildExportBar(),
          ]),
          if (_exporting)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_entries.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bookmark_border_rounded, size: 64, color: AppTheme.textTertiary),
          SizedBox(height: 16),
          Text('No words saved yet',
              style: TextStyle(fontSize: 17, color: AppTheme.textSecondary)),
          SizedBox(height: 6),
          Text('Tap words while reading to save them',
              style: TextStyle(fontSize: 14, color: AppTheme.textTertiary)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final e = _entries[i];
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_rounded, color: AppTheme.danger),
          ),
          onDismissed: (_) => _delete(e),
          child: _VocabCard(entry: e, onEdit: () => _edit(e)),
        );
      },
    );
  }

  Widget _buildExportBar() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.separator)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('EXPORT AS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTertiary,
                  letterSpacing: 0.8)),
          const SizedBox(height: 10),
          Row(children: [
            _ExpBtn(emoji: '🃏', label: 'Anki',     sub: '.apkg', onTap: () => _export('apkg')),
            _ExpBtn(emoji: '📄', label: 'PDF',       sub: '.pdf',  onTap: () => _export('pdf')),
            _ExpBtn(emoji: '📝', label: 'Detailed',  sub: '.txt',  onTap: () => _export('txt_detailed')),
            _ExpBtn(emoji: '📋', label: 'Words',     sub: '.txt',  onTap: () => _export('txt_words'), last: true),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VocabCard extends StatelessWidget {
  final VocabEntry entry;
  final VoidCallback? onEdit;
  const _VocabCard({required this.entry, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(entry.word,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          if (entry.partOfSpeech.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.partOfSpeech,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: onEdit,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.edit_rounded, size: 17, color: AppTheme.textTertiary),
            ),
          ),
        ]),
        if (entry.definition.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(entry.definition,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
        ],
        if (entry.chineseMeaning.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(entry.chineseMeaning,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1A7A1A), height: 1.4)),
        ],
        if (entry.sentence.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('"${entry.sentence}"',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                  fontStyle: FontStyle.italic,
                  height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
        if (entry.source.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('— ${entry.source}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textTertiary)),
          ),
        ],
      ]),
    );
  }
}

class _ExpBtn extends StatelessWidget {
  final String emoji;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool last;

  const _ExpBtn({
    required this.emoji,
    required this.label,
    required this.sub,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(right: last ? 0 : 8),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            Text(sub,
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.textTertiary)),
          ]),
        ),
      ),
    );
  }
}

// ── 编辑底部面板 ──────────────────────────────────────────────────────────────

class _EditSheet extends StatelessWidget {
  final String word;
  final TextEditingController phoneticCtrl;
  final TextEditingController posCtrl;
  final TextEditingController defCtrl;
  final TextEditingController cnCtrl;
  final TextEditingController sentCtrl;

  const _EditSheet({
    required this.word,
    required this.phoneticCtrl,
    required this.posCtrl,
    required this.defCtrl,
    required this.cnCtrl,
    required this.sentCtrl,
  });

  Widget _field(TextEditingController ctrl, String label,
      {String hint = '', int maxLines = 1, int minLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        minLines: minLines,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFFDDDDDD))),
          enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFFDDDDDD))),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }

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
            _field(phoneticCtrl, '音标', hint: '如 /wɜːrd/'),
            _field(posCtrl, '词性', hint: '如 noun / verb / adj'),
            _field(defCtrl, '定义', hint: '英文解释', maxLines: 3, minLines: 2),
            _field(cnCtrl, '翻译', hint: '中文翻译', maxLines: 2),
            _field(sentCtrl, '例句', maxLines: 4, minLines: 2),
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
