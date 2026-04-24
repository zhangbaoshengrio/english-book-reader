import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/dict_source.dart'; // DictSource + DictLogo
import '../services/database_service.dart';
import '../services/mdx_service.dart';
import '../theme/app_theme.dart';

// ── Remote dict descriptor (hardcoded from ereader.link/mdicts/mdicts.json) ───

class _RemoteDict {
  final String title;
  final String desc;
  final String mdxFileName;
  final String downloadUrl;
  final int fileSize; // bytes

  const _RemoteDict({
    required this.title,
    required this.desc,
    required this.mdxFileName,
    required this.downloadUrl,
    required this.fileSize,
  });

  String get fileSizeLabel {
    final mb = fileSize / 1048576;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

const _kRemoteDicts = [
  _RemoteDict(
    title: '牛津10英汉双解词典',
    desc: '英汉双解，词条28万，样式精美，强烈推荐',
    mdxFileName: '牛津高阶第10版英汉双解V5_0.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E7%89%9B%E6%B4%A510%E8%8B%B1%E6%B1%89%E5%8F%8C%E8%A7%A3%E8%AF%8D%E5%85%B8.zip',
    fileSize: 58350520,
  ),
  _RemoteDict(
    title: '柯林斯8英英版',
    desc: '英英词典首选，词条21万',
    mdxFileName: 'Collins COBUILD Advanced English Dictionary Online.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E6%9F%AF%E6%9E%97%E6%96%AF8%E8%8B%B1%E8%8B%B1%E7%89%88.zip',
    fileSize: 16575949,
  ),
  _RemoteDict(
    title: '21世纪英汉词典',
    desc: '词条40万，覆盖当代用语',
    mdxFileName: '21世纪大英汉词典.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/21%E4%B8%96%E7%BA%AA%E8%8B%B1%E6%B1%89%E8%AF%8D%E5%85%B8.zip',
    fileSize: 26999105,
  ),
  _RemoteDict(
    title: '美国传统英汉双解词典',
    desc: '英汉双解，词条4万',
    mdxFileName: 'American Heritage English-Chinese Dictionary.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E7%BE%8E%E5%9B%BD%E4%BC%A0%E7%BB%9F%E8%8B%B1%E6%B1%89%E5%8F%8C%E8%A7%A3%E8%AF%8D%E5%85%B8.zip',
    fileSize: 30099958,
  ),
  _RemoteDict(
    title: '麦克米伦英英',
    desc: '释义准确简明，词条17万',
    mdxFileName: 'MacmillanEnEn.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E9%BA%A6%E5%85%8B%E7%B1%B3%E4%BC%A6%E8%8B%B1%E8%8B%B1.zip',
    fileSize: 73157714,
  ),
  _RemoteDict(
    title: '牛津高阶第九版英英',
    desc: '适合英语学习者，词条18万',
    mdxFileName: 'OALD9.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E7%89%9B%E6%B4%A5%E9%AB%98%E9%98%B6%E7%AC%AC%E4%B9%9D%E7%89%88%E8%8B%B1%E8%8B%B1.zip',
    fileSize: 29374421,
  ),
  _RemoteDict(
    title: '朗文6英英版',
    desc: '当代英语学习词典，词条23万',
    mdxFileName: 'LongmanDictionaryOfContemporaryEnglish6thEnEn.mdx',
    downloadUrl:
        'https://ereader.link/mdicts/%E6%9C%97%E6%96%876%E8%8B%B1%E8%8B%B1%E7%89%88.zip',
    fileSize: 160747828,
  ),
];

// ── Download state ─────────────────────────────────────────────────────────────

enum _DlPhase { downloading, extracting, indexing, done, error }

class _DlState {
  final _DlPhase phase;
  final double progress;
  final String? error;
  const _DlState({required this.phase, this.progress = 0, this.error});
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class DictManagerScreen extends StatefulWidget {
  const DictManagerScreen({super.key});
  @override
  State<DictManagerScreen> createState() => _DictManagerScreenState();
}

class _DictManagerScreenState extends State<DictManagerScreen> {
  List<DictSource> _sources = [];
  bool _loading = true;

  // download state keyed by mdxFileName
  final Map<String, _DlState> _dlStates = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DatabaseService.getAllDictSources();
    if (mounted) setState(() { _sources = s; _loading = false; });
  }

  // ── Check installed ────────────────────────────────────────────────────────

  bool _isInstalled(_RemoteDict rd) =>
      _sources.any((s) => p.basename(s.filePath) == rd.mdxFileName);

  // ── Remote download ────────────────────────────────────────────────────────

  Future<void> _downloadDict(_RemoteDict rd) async {
    final key = rd.mdxFileName;

    setState(() => _dlStates[key] = const _DlState(phase: _DlPhase.downloading));

    try {
      // ── 1. Stream-download the zip ─────────────────────────────────────────
      final uri = Uri.parse(rd.downloadUrl);
      final req = http.Request('GET', uri);
      final client = http.Client();
      final resp = await client.send(req);
      final total =
          resp.contentLength != null && resp.contentLength! > 0
              ? resp.contentLength!
              : rd.fileSize;

      final bytes = <int>[];
      int received = 0;
      await for (final chunk in resp.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (mounted) {
          setState(() => _dlStates[key] =
              _DlState(phase: _DlPhase.downloading, progress: received / total));
        }
      }
      client.close();

      // ── 2. Extract .mdx from zip ──────────────────────────────────────────
      if (mounted) setState(() => _dlStates[key] = const _DlState(phase: _DlPhase.extracting));

      final archive = ZipDecoder().decodeBytes(bytes);
      final mdxEntry = archive.files.firstWhere(
        (f) => f.name.toLowerCase().endsWith('.mdx'),
        orElse: () => throw Exception('zip 中找不到 .mdx 文件'),
      );
      if (!mdxEntry.isFile) throw Exception('zip 条目不是文件');

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(docsDir.path, 'dicts'));
      await destDir.create(recursive: true);
      final destPath = p.join(destDir.path, rd.mdxFileName);
      await File(destPath).writeAsBytes(mdxEntry.content as List<int>);

      // ── 3. Build MDict index ──────────────────────────────────────────────
      if (mounted) setState(() => _dlStates[key] = const _DlState(phase: _DlPhase.indexing));

      // Always call buildIndex — it internally skips if already complete,
      // and rebuilds if the index file exists but is empty/broken.
      await MdxService.buildIndex(destPath, (prog, _) {
        if (mounted) {
          setState(() => _dlStates[key] =
              _DlState(phase: _DlPhase.indexing, progress: prog));
        }
      });

      // ── 4. Save to DB ─────────────────────────────────────────────────────
      final src = DictSource(
        name: rd.title,
        filePath: destPath,
        type: 'mdx',
        addedAt: DateTime.now(),
      );
      await DatabaseService.addDictSource(src);
      await _load();

      if (mounted) setState(() => _dlStates[key] = const _DlState(phase: _DlPhase.done));
    } catch (e) {
      if (mounted) {
        setState(() => _dlStates[key] =
            _DlState(phase: _DlPhase.error, error: e.toString()));
      }
    }
  }

  // ── Import from file picker ────────────────────────────────────────────────

  void _showImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportSheet(onImport: _importDict),
    );
  }

  Future<void> _importDict(String format) async {
    Navigator.of(context).pop();

    FilePickerResult? result;
    if (format == 'tsv') {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tsv', 'csv', 'txt'],
      );
    } else {
      result = await FilePicker.platform.pickFiles(type: FileType.any);
    }
    if (result == null || result.files.single.path == null) return;

    final srcPath = result.files.single.path!;
    final fileName = result.files.single.name;

    if (format == 'mdx') {
      await _importMdx(srcPath, fileName);
    } else {
      await _importSimple(srcPath, fileName, format);
    }
  }

  Future<void> _importMdx(String srcPath, String fileName) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final destPath = p.join(docsDir.path, 'dicts', fileName);
    await Directory(p.dirname(destPath)).create(recursive: true);

    if (!await File(destPath).exists()) {
      _snack('正在复制文件...');
      await File(srcPath).copy(destPath);
    }

    double prog = 0;
    String status = '准备中...';
    bool done = false;
    StateSetter? setS;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, ss) {
          setS = ss;
          return AlertDialog(
            title: const Text('正在建立索引'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: prog, color: AppTheme.primary),
              const SizedBox(height: 12),
              Text(status,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              if (done)
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('完成'),
                ),
            ]),
          );
        },
      ),
    );

    try {
      final count = await MdxService.buildIndex(destPath, (p2, s2) {
        prog = p2;
        status = s2;
        setS?.call(() {});
      });
      final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final src = DictSource(
          name: name, filePath: destPath, type: 'mdx', addedAt: DateTime.now());
      await DatabaseService.addDictSource(src);
      await _load();
      done = true;
      prog = 1.0;
      status = '完成！共 $count 词条';
      setS?.call(() {});
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _snack('导入失败: $e');
    }
  }

  Future<void> _importSimple(
      String srcPath, String fileName, String format) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final destPath = p.join(docsDir.path, 'dicts', fileName);
    await Directory(p.dirname(destPath)).create(recursive: true);
    await File(srcPath).copy(destPath);

    final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final src = DictSource(
        name: name, filePath: destPath, type: format, addedAt: DateTime.now());
    await DatabaseService.addDictSource(src);
    await _load();
    _snack('词典 "$name" 导入成功');
  }

  Future<void> _toggleEnabled(DictSource src) async {
    await DatabaseService.updateDictEnabled(src.id!, !src.enabled);
    await _load();
  }

  Future<void> _delete(DictSource src) async {
    await DatabaseService.deleteDictSource(src.id!);
    try {
      File(src.filePath).deleteSync();
      final idxFile = File('${src.filePath}.idx.db');
      if (idxFile.existsSync()) idxFile.deleteSync();
    } catch (_) {}
    await _load();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = List<DictSource>.from(_sources);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() => _sources = list);
    final ids = list.map((s) => s.id!).toList();
    await DatabaseService.updateDictOrder(ids);
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.groupedBg,
      appBar: AppBar(
        title: const Text('词典管理'),
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppTheme.primary,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            color: AppTheme.primary,
            tooltip: '导入词典',
            onPressed: _showImportSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return CustomScrollView(
      slivers: [
        // ── Installed dicts (reorderable) ──────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(children: [
              const _SectionTitle('词典顺序'),
              const SizedBox(width: 6),
              Text('长按拖动排序',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _sources.isEmpty
                ? Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(children: [
                      Icon(Icons.import_contacts_outlined,
                          size: 40, color: AppTheme.textTertiary),
                      SizedBox(height: 10),
                      Text('点击右上角 + 导入词典',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                    ]),
                  )
                : ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: _onReorder,
                    proxyDecorator: (child, _, __) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    children: [
                      for (final src in _sources)
                        _DictCard(
                          key: ValueKey(src.id),
                          source: src,
                          onToggle: () => _toggleEnabled(src),
                          onDelete: src.isBuiltin ? null : () => _delete(src),
                        ),
                    ],
                  ),
          ),
        ),

        // ── Downloadable dicts ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: const _SectionTitle('下载更多词典'),
          ),
        ),
        SliverToBoxAdapter(
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '以下词典由 ereader.link 提供，免费下载，下载后自动导入',
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RemoteDictCard(
                rd: _kRemoteDicts[i],
                installed: _isInstalled(_kRemoteDicts[i]),
                dlState: _dlStates[_kRemoteDicts[i].mdxFileName],
                onDownload: () => _downloadDict(_kRemoteDicts[i]),
                onRetry: () {
                  setState(() => _dlStates.remove(_kRemoteDicts[i].mdxFileName));
                  _downloadDict(_kRemoteDicts[i]);
                },
              ),
            ),
            childCount: _kRemoteDicts.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ── Remote dict card ───────────────────────────────────────────────────────────

class _RemoteDictCard extends StatelessWidget {
  final _RemoteDict rd;
  final bool installed;
  final _DlState? dlState;
  final VoidCallback onDownload;
  final VoidCallback onRetry;

  const _RemoteDictCard({
    required this.rd,
    required this.installed,
    required this.dlState,
    required this.onDownload,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final phase = dlState?.phase;
    final progress = dlState?.progress ?? 0.0;
    final isActive = phase == _DlPhase.downloading ||
        phase == _DlPhase.extracting ||
        phase == _DlPhase.indexing;

    String phaseLabel() {
      switch (phase) {
        case _DlPhase.downloading:
          return '下载中 ${(progress * 100).toStringAsFixed(0)}%';
        case _DlPhase.extracting:
          return '解压中...';
        case _DlPhase.indexing:
          return '建立索引 ${(progress * 100).toStringAsFixed(0)}%';
        case _DlPhase.error:
          return '下载失败';
        case _DlPhase.done:
          return '下载完成';
        default:
          return '';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.menu_book_rounded,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          // Name + desc
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rd.title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(rd.desc,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ]),
          ),
          const SizedBox(width: 10),
          // Action button
          _buildActionButton(installed, phase, progress),
        ]),

        // Phase label (only shown when active)
        if (isActive) ...[
          const SizedBox(height: 6),
          Text(phaseLabel(),
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],

        // Error message
        if (phase == _DlPhase.error) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline_rounded,
                size: 13, color: AppTheme.danger),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                dlState!.error ?? '未知错误',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.danger),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onRetry,
            child: const Text('重试',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }

  Widget _buildActionButton(
      bool installed, _DlPhase? phase, double progress) {
    if (installed || phase == _DlPhase.done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('已安装',
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.primary,
                fontWeight: FontWeight.w600)),
      );
    }

    if (phase == _DlPhase.downloading || phase == _DlPhase.indexing) {
      return _ArcProgress(progress: progress);
    }

    if (phase == _DlPhase.extracting) {
      return const _ArcProgress(progress: 0, indeterminate: true);
    }

    if (phase == _DlPhase.error) {
      return const SizedBox.shrink();
    }

    // idle
    return GestureDetector(
      onTap: onDownload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          const Text('下载',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          Text(rd.fileSizeLabel,
              style: const TextStyle(fontSize: 9, color: Colors.white70)),
        ]),
      ),
    );
  }
}

// ── Import bottom sheet ────────────────────────────────────────────────────────

class _ImportSheet extends StatelessWidget {
  final void Function(String format) onImport;
  const _ImportSheet({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const Text('导入词典',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('选择词典格式，导入后可离线查词',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 20),
          _FormatCard(
            icon: Icons.menu_book_rounded,
            title: 'MDict 词典 (.mdx)',
            color: const Color(0xFF5C6BC0),
            description: '支持最广泛的词典格式，如朗文、牛津、柯林斯等。\n'
                '首次导入需建立索引，较大词典约需1-3分钟',
            onTap: () => onImport('mdx'),
          ),
          const SizedBox(height: 12),
          _FormatCard(
            icon: Icons.storage_rounded,
            title: 'ECDICT 离线词典 (.db)',
            color: const Color(0xFF26A69A),
            description: '免费英汉词典，含 330,000+ 词条，支持离线使用。\n'
                'github.com/skywind3000/ECDICT 下载 ecdict.db',
            onTap: () => onImport('ecdict'),
          ),
          const SizedBox(height: 12),
          _FormatCard(
            icon: Icons.text_snippet_outlined,
            title: '文本词典 (.tsv / .csv)',
            color: const Color(0xFFFFA726),
            description: '制表符分隔格式，每行一个词条。\n'
                '格式：单词\\t释义（TSV）或 单词,释义（CSV）',
            onTap: () => onImport('tsv'),
          ),
        ],
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String description;
  final VoidCallback onTap;

  const _FormatCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  const SizedBox(height: 5),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.5)),
                ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 10),
            child: Icon(Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.6)),
          ),
        ]),
      ),
    );
  }
}

// ── Circular arc progress ──────────────────────────────────────────────────────

class _ArcProgress extends StatelessWidget {
  final double progress;   // 0.0 – 1.0
  final bool indeterminate;

  const _ArcProgress({required this.progress, this.indeterminate = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CircularProgressIndicator(
        value: indeterminate ? null : progress,
        strokeWidth: 3,
        color: AppTheme.primary,
        backgroundColor: const Color(0xFFDCEAFF),
      ),
    );
  }
}

// ── Section title ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3));
  }
}

// ── Installed dict card ────────────────────────────────────────────────────────

class _DictCard extends StatelessWidget {
  final DictSource source;
  final VoidCallback onToggle;
  final VoidCallback? onDelete; // null = built-in (no delete)

  const _DictCard({
    super.key,
    required this.source,
    required this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final logo = DictLogo.of(source);
    final logoColor = Color(logo.argb);
    final exists = source.isBuiltin || File(source.filePath).existsSync();

    Widget card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(children: [
        // Drag handle
        Icon(Icons.drag_handle_rounded, size: 20, color: Colors.grey[400]),
        const SizedBox(width: 10),
        // Logo badge
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: logoColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(logo.char,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: logoColor)),
          ),
        ),
        const SizedBox(width: 10),
        // Name + type
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(source.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(
              source.isBuiltin ? '内置词典' : source.type.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary),
            ),
            if (!exists)
              const Text('文件不存在',
                  style: TextStyle(fontSize: 10, color: AppTheme.danger)),
          ]),
        ),
        // Delete button (custom dicts only)
        if (onDelete != null)
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppTheme.danger),
            ),
          ),
        // Toggle
        Switch(
          value: source.enabled,
          onChanged: (_) => onToggle(),
          activeThumbColor: logoColor,
          activeTrackColor: logoColor.withValues(alpha: 0.3),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );

    // Wrap custom dicts with swipe-to-delete
    if (onDelete != null) {
      card = Dismissible(
        key: ValueKey('dismiss_${source.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete_rounded, color: AppTheme.danger),
        ),
        onDismissed: (_) => onDelete!(),
        child: card,
      );
    }

    return card;
  }
}
