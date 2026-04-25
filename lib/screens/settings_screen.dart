import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'ai_engine_screen.dart';
import 'dict_manager_screen.dart';
import 'translation_engine_screen.dart';
import 'voice_engine_screen.dart';
import 'vocab_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _fontSize      = 18;
  double _lineHeight    = 1.9;
  double _margin        = 22;
  String _theme         = ReaderTheme.paper;
  String _fontFamily    = 'Georgia';
  String _pageTurnStyle = PageTurnStyle.scroll;

  @override
  void initState() {
    super.initState();
    _load();
  }


  Future<void> _load() async {
    final results = await Future.wait([
      SettingsService.getFontSize(),
      SettingsService.getLineHeight(),
      SettingsService.getTheme(),
      SettingsService.getFontFamily(),
      SettingsService.getMargin(),
      SettingsService.getPageTurnStyle(),
    ]);
    if (!mounted) return;
    setState(() {
      _fontSize         = results[0] as double;
      _lineHeight       = results[1] as double;
      _theme            = results[2] as String;
      _fontFamily       = results[3] as String;
      _margin           = results[4] as double;
      _pageTurnStyle    = results[5] as String;
    });
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
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // ── 阅读外观 ────────────────────────────────────────────────────────
          _SectionHeader('阅读外观'),
          _Card(children: [
            // Background theme
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('背景主题',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  Row(children: [
                    _ThemeChip(label: '米色', value: ReaderTheme.paper,
                        bg: const Color(0xFFFDF8F0), current: _theme,
                        onTap: (v) => _setTheme(v)),
                    const SizedBox(width: 10),
                    _ThemeChip(label: '白色', value: ReaderTheme.white,
                        bg: Colors.white, current: _theme,
                        onTap: (v) => _setTheme(v)),
                    const SizedBox(width: 10),
                    _ThemeChip(label: '暗色', value: ReaderTheme.dark,
                        bg: const Color(0xFF1C1C1E), current: _theme,
                        onTap: (v) => _setTheme(v),
                        textColor: Colors.white70),
                  ]),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Font size
            _SliderRow(
              label: '字体大小',
              value: _fontSize,
              min: 14, max: 26, divisions: 12,
              display: '${_fontSize.round()}px',
              onChanged: (v) => setState(() => _fontSize = v),
              onChangeEnd: (v) => SettingsService.setFontSize(v),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Line height
            _SliderRow(
              label: '行间距',
              value: _lineHeight,
              min: 1.4, max: 2.4, divisions: 10,
              display: _lineHeight.toStringAsFixed(1),
              onChanged: (v) => setState(() => _lineHeight = v),
              onChangeEnd: (v) => SettingsService.setLineHeight(v),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Margin
            _SliderRow(
              label: '页面边距',
              value: _margin,
              min: 8, max: 40, divisions: 8,
              display: '${_margin.round()}px',
              onChanged: (v) => setState(() => _margin = v),
              onChangeEnd: (v) => SettingsService.setMargin(v),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Font family
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                const Expanded(child: Text('字体', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                _FontButton(label: 'Georgia',   current: _fontFamily, onTap: _setFont),
                const SizedBox(width: 8),
                _FontButton(label: 'Serif',     current: _fontFamily, onTap: _setFont),
                const SizedBox(width: 8),
                _FontButton(label: 'SansSerif', display: '无衬线', current: _fontFamily, onTap: _setFont),
              ]),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Page turn style
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(children: [
                const Expanded(child: Text('翻页方式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                _SegmentedPicker(
                  options: const [
                    (PageTurnStyle.scroll, '上下滚动'),
                    (PageTurnStyle.swipe,  '左右滑动'),
                  ],
                  current: _pageTurnStyle,
                  onTap: (v) {
                    setState(() => _pageTurnStyle = v);
                    SettingsService.setPageTurnStyle(v);
                  },
                ),
              ]),
            ),
          ]),

          // ── 翻译 & 语音 ───────────────────────────────────────────────────────
          _SectionHeader('翻译与语音'),
          _Card(children: [
            _NavRow(
              icon: Icons.translate_rounded,
              label: '翻译引擎',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TranslationEngineScreen())),
            ),
            const Divider(height: 1, indent: 52, endIndent: 0),
            _NavRow(
              icon: Icons.auto_awesome_rounded,
              label: 'AI 引擎',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AiEngineScreen())),
            ),
            const Divider(height: 1, indent: 52, endIndent: 0),
            _NavRow(
              icon: Icons.record_voice_over_rounded,
              label: '语音引擎',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const VoiceEngineScreen())),
            ),
          ]),

          // ── 词典 & 词汇 ──────────────────────────────────────────────────────
          _SectionHeader('词典与词汇'),
          _Card(children: [
            _NavRow(
              icon: Icons.menu_book_rounded,
              label: '词典管理',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DictManagerScreen())),
            ),
            const Divider(height: 1, indent: 52, endIndent: 0),
            _NavRow(
              icon: Icons.bookmark_rounded,
              label: '我的词汇本',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const VocabScreen())),
            ),
          ]),

          // ── 数据备份 ─────────────────────────────────────────────────────────
          _SectionHeader('数据备份'),
          _Card(children: [
            _NavRow(
              icon: Icons.upload_rounded,
              label: '备份词汇本',
              onTap: _backup,
            ),
            const Divider(height: 1, indent: 52, endIndent: 0),
            _NavRow(
              icon: Icons.download_rounded,
              label: '恢复词汇本',
              onTap: _restore,
            ),
          ]),

          // ── 关于 ─────────────────────────────────────────────────────────────
          _SectionHeader('关于'),
          _Card(children: [
            const ListTile(
              leading: Icon(Icons.auto_stories_rounded, color: AppTheme.primary, size: 22),
              title: Text('English Book Reader', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              subtitle: Text('专注英文阅读的词典 & 词汇工具', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _setTheme(String v) {
    setState(() => _theme = v);
    SettingsService.setTheme(v);
  }

  void _setFont(String v) {
    setState(() => _fontFamily = v);
    SettingsService.setFontFamily(v);
  }

  Future<void> _backup() async {
    try {
      final entries = await DatabaseService.getAllWords();
      if (entries.isEmpty) {
        _snack('词汇本为空，无需备份');
        return;
      }
      final dir  = await getTemporaryDirectory();
      final file = await ExportService.exportBackup(entries, dir.path);
      await Share.shareXFiles([XFile(file.path)], text: '词汇本备份');
    } catch (e) {
      _snack('备份失败：$e');
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await io.File(result.files.single.path!).readAsString();
      final entries = ExportService.parseBackup(content);
      if (entries.isEmpty) { _snack('备份文件没有词条'); return; }

      // Ask user: merge or overwrite?
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复词汇本'),
          content: Text('找到 ${entries.length} 个词条。\n\n选择恢复方式：'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'merge'),
                child: const Text('合并（保留现有）')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'overwrite'),
                child: Text('覆盖', style: TextStyle(color: Colors.red.shade600))),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;

      if (choice == 'overwrite') {
        await DatabaseService.clearAllWords();
      }
      for (final e in entries) {
        await DatabaseService.addOrUpdateWord(e);
      }
      if (mounted) _snack('已恢复 ${entries.length} 个词条');
    } catch (e) {
      _snack('恢复失败：文件格式有误');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.3)),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: children),
      );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(display,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppTheme.primary,
              inactiveColor: AppTheme.primary.withValues(alpha: 0.2),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final Color bg;
  final Color textColor;
  final void Function(String) onTap;

  const _ThemeChip({
    required this.label,
    required this.value,
    required this.current,
    required this.bg,
    required this.onTap,
    this.textColor = const Color(0xFF333333),
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        width: 68,
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : const Color(0xFFDDDDDD),
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppTheme.primary : textColor)),
      ),
    );
  }
}

class _FontButton extends StatelessWidget {
  final String label;
  final String? display;
  final String current;
  final void Function(String) onTap;

  const _FontButton({
    required this.label,
    this.display,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = label == current;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(display ?? label,
            style: TextStyle(
                fontSize: 12,
                fontFamily: label == 'SansSerif' ? null : label,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color:
                    selected ? AppTheme.primary : AppTheme.textSecondary)),
      ),
    );
  }
}

/// Two-option inline segmented picker (no Material SegmentedButton needed).
class _SegmentedPicker extends StatelessWidget {
  final List<(String, String)> options; // (value, label)
  final String current;
  final void Function(String) onTap;

  const _SegmentedPicker({
    required this.options,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((opt) {
        final selected = opt.$1 == current;
        return GestureDetector(
          onTap: () => onTap(opt.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            margin: EdgeInsets.only(left: opt == options.first ? 0 : 6),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? AppTheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(opt.$2,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? AppTheme.primary : AppTheme.textSecondary)),
          ),
        );
      }).toList(),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 22),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppTheme.textTertiary, size: 20),
      onTap: onTap,
    );
  }
}

