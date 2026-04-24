class DictSource {
  final int? id;
  final String name;
  final String filePath; // 'builtin:gaojie' | 'builtin:xuexie' | ... | real path
  final String type;     // 'builtin' | 'mdx' | 'ecdict' | 'tsv'
  final bool enabled;
  final int sortOrder;
  final DateTime addedAt;

  const DictSource({
    this.id,
    required this.name,
    required this.filePath,
    required this.type,
    this.enabled = true,
    this.sortOrder = 999,
    required this.addedAt,
  });

  bool get isBuiltin => type == 'builtin';

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'file_path': filePath,
        'type': type,
        'enabled': enabled ? 1 : 0,
        'sort_order': sortOrder,
        'added_at': addedAt.millisecondsSinceEpoch,
      };

  static DictSource fromMap(Map<String, dynamic> m) => DictSource(
        id: m['id'] as int?,
        name: m['name'] as String,
        filePath: m['file_path'] as String,
        type: m['type'] as String,
        enabled: (m['enabled'] as int?) == 1,
        sortOrder: (m['sort_order'] as int?) ?? 999,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );
}

/// Logo info (char + color index) for UI — defined here to keep model self-contained.
class DictLogo {
  final String char;
  final int colorIndex; // index into _kLogoColors

  const DictLogo(this.char, this.colorIndex);

  static DictLogo of(DictSource src) {
    switch (src.filePath) {
      case 'builtin:gaojie':   return const DictLogo('高', 0);
      case 'builtin:xuexie':   return const DictLogo('学', 1);
      case 'builtin:jianming': return const DictLogo('简', 2);
      case 'builtin:freedict': return const DictLogo('F',  3);
      case 'builtin:oxford':   return const DictLogo('牛', 4);
      case 'builtin:c21':      return const DictLogo('世', 5);
      case 'builtin:aher':     return const DictLogo('美', 6);
      default:
        final n = src.name;
        if (n.contains('牛津') || n.contains('Oxford') || n.contains('OALD'))
          return const DictLogo('牛', 4);
        if (n.contains('21世纪') || n.contains('21 Century'))
          return const DictLogo('世', 5);
        if (n.contains('柯林斯') || n.contains('Collins'))
          return const DictLogo('柯', 1);
        if (n.contains('美国传统') || n.contains('Heritage'))
          return const DictLogo('美', 6);
        if (n.contains('麦克米伦') || n.contains('Macmillan'))
          return const DictLogo('麦', 3);
        if (n.contains('朗文') || n.contains('Longman'))
          return const DictLogo('朗', 0);
        final ch = n.isNotEmpty ? n[0] : '?';
        final idx = n.codeUnits.fold(0, (a, b) => (a * 31 + b) & 0x7FFFFFFF) % 4 + 4;
        return DictLogo(ch, idx);
    }
  }

  // Colors: [0]=red [1]=blue [2]=green [3]=orange [4]=purple [5]=cyan [6]=indigo [7..]=custom
  static const _kLogoColors = [
    0xFFD63031, // red    (高)
    0xFF0984E3, // blue   (学)
    0xFF00B894, // teal   (简)
    0xFFE17055, // orange (F)
    0xFF6C5CE7, // purple (牛)
    0xFF00B4D8, // cyan   (世)
    0xFF3A86FF, // indigo (美)
    0xFFE84393, // pink
  ];

  int get argb => _kLogoColors[colorIndex.clamp(0, _kLogoColors.length - 1)];
}
