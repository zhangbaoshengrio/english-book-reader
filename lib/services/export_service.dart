import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';
import '../models/vocab_entry.dart';

class ExportService {
  // ── TXT detailed ──────────────────────────────────────────────────────────
  static Future<File> exportTxtDetailed(
      List<VocabEntry> entries, String dir) async {
    final sorted = [...entries]..sort((a, b) => a.word.compareTo(b.word));
    final sb = StringBuffer()
      ..writeln('Vocabulary List — Detailed Export')
      ..writeln('=' * 50)
      ..writeln();

    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      sb.writeln('${i + 1}. ${e.word}');
      if (e.phonetic.isNotEmpty)       sb.writeln('   Phonetic        : ${e.phonetic}');
      if (e.partOfSpeech.isNotEmpty)   sb.writeln('   Part of speech  : ${e.partOfSpeech}');
      if (e.definition.isNotEmpty)     sb.writeln('   Definition      : ${e.definition}');
      if (e.chineseMeaning.isNotEmpty) sb.writeln('   Translation     : ${e.chineseMeaning}');
      if (e.sentence.isNotEmpty)       sb.writeln('   Sentence        : ${e.sentence}');
      if (e.source.isNotEmpty)         sb.writeln('   Source          : ${e.source}');
      sb.writeln();
    }

    final file = File(p.join(dir, 'vocabulary_detailed.txt'));
    await file.writeAsString(sb.toString(), encoding: utf8);
    return file;
  }

  // ── TXT words only ────────────────────────────────────────────────────────
  static Future<File> exportTxtWords(
      List<VocabEntry> entries, String dir) async {
    final words = entries.map((e) => e.word.toLowerCase()).toSet().toList()
      ..sort();
    final file = File(p.join(dir, 'vocabulary_words.txt'));
    await file.writeAsString(words.join('\n'), encoding: utf8);
    return file;
  }

  // ── PDF ───────────────────────────────────────────────────────────────────
  static Future<File> exportPdf(
      List<VocabEntry> entries, String dir) async {
    final sorted = [...entries]..sort((a, b) => a.word.compareTo(b.word));
    final doc    = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Vocabulary List',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ),
      build: (ctx) {
        return [
          for (var i = 0; i < sorted.length; i++)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(width: 3, color: PdfColors.blue),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Text('${i + 1}. ${sorted[i].word}',
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold)),
                    if (sorted[i].partOfSpeech.isNotEmpty) ...[
                      pw.SizedBox(width: 8),
                      pw.Text('(${sorted[i].partOfSpeech})',
                          style: const pw.TextStyle(
                              fontSize: 11, color: PdfColors.blue600)),
                    ],
                  ]),
                  if (sorted[i].definition.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text(sorted[i].definition,
                          style: const pw.TextStyle(fontSize: 11)),
                    ),
                  if (sorted[i].sentence.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text('"${sorted[i].sentence}"',
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontStyle: pw.FontStyle.italic,
                              color: PdfColors.grey600)),
                    ),
                  if (sorted[i].source.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('— ${sorted[i].source}',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey)),
                      ),
                    ),
                ],
              ),
            ),
        ];
      },
    ));

    final file = File(p.join(dir, 'vocabulary.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // ── APKG (Anki) ───────────────────────────────────────────────────────────
  static Future<File> exportApkg(
      List<VocabEntry> entries, String dir) async {
    // Build the Anki SQLite database in memory-equivalent temp path
    final dbPath = p.join(dir, '_anki_tmp.anki2');
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();

    final db = await openDatabase(dbPath);
    await _buildAnkiDb(db, entries);
    await db.close();

    // Create the media manifest (no media files)
    final mediaPath = p.join(dir, '_anki_media');
    await File(mediaPath).writeAsString('{}');

    // Zip both files into .apkg
    final dbBytes    = await File(dbPath).readAsBytes();
    final mediaBytes = Uint8List.fromList(utf8.encode("{}"));

    final archive = Archive()
      ..addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes))
      ..addFile(ArchiveFile('media', mediaBytes.length, mediaBytes));

    final apkgBytes = ZipEncoder().encode(archive)!;
    final apkgFile  = File(p.join(dir, 'vocabulary.apkg'));
    await apkgFile.writeAsBytes(apkgBytes);

    // Cleanup temp files
    for (final tmp in [dbPath, mediaPath]) {
      try { File(tmp).deleteSync(); } catch (_) {}
    }
    return apkgFile;
  }

  // ── JSON Backup ───────────────────────────────────────────────────────────
  /// Export all entries to a JSON backup file. Returns the file for sharing.
  static Future<File> exportBackup(
      List<VocabEntry> entries, String dir) async {
    final data = entries.map((e) => {
      'word':            e.word,
      'phonetic':        e.phonetic,
      'part_of_speech':  e.partOfSpeech,
      'definition':      e.definition,
      'chinese_meaning': e.chineseMeaning,
      'sentence':        e.sentence,
      'source':          e.source,
      'added_at':        e.addedAt.toIso8601String(),
    }).toList();
    final json = JsonEncoder.withIndent('  ').convert({'version': 1, 'entries': data});
    final ts   = DateTime.now().toString().replaceAll(RegExp(r'[: ]'), '-').substring(0, 19);
    final file = File(p.join(dir, 'vocab_backup_$ts.json'));
    await file.writeAsString(json, encoding: utf8);
    return file;
  }

  /// Parse a backup JSON and return the list of VocabEntry objects.
  /// Throws if the file is not a valid backup.
  static List<VocabEntry> parseBackup(String jsonStr) {
    final map  = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (map['entries'] as List).cast<Map<String, dynamic>>();
    return list.map((m) => VocabEntry(
      word:           (m['word']            as String?) ?? '',
      phonetic:       (m['phonetic']         as String?) ?? '',
      partOfSpeech:   (m['part_of_speech']   as String?) ?? '',
      definition:     (m['definition']       as String?) ?? '',
      chineseMeaning: (m['chinese_meaning']  as String?) ?? '',
      sentence:       (m['sentence']         as String?) ?? '',
      source:         (m['source']           as String?) ?? '',
      addedAt:       m['added_at'] != null
                       ? DateTime.tryParse(m['added_at'] as String) ?? DateTime.now()
                       : DateTime.now(),
    )).toList();
  }

  static Future<void> _buildAnkiDb(
      Database db, List<VocabEntry> entries) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const modelId = 1607392319;
    const deckId  = 1;

    await db.execute('''CREATE TABLE col (
      id INTEGER PRIMARY KEY, crt INTEGER NOT NULL, mod INTEGER NOT NULL,
      scm INTEGER NOT NULL, ver INTEGER NOT NULL, dty INTEGER NOT NULL,
      usn INTEGER NOT NULL, ls INTEGER NOT NULL, conf TEXT NOT NULL,
      models TEXT NOT NULL, decks TEXT NOT NULL, dconf TEXT NOT NULL,
      tags TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE notes (
      id INTEGER PRIMARY KEY, guid TEXT NOT NULL, mid INTEGER NOT NULL,
      mod INTEGER NOT NULL, usn INTEGER NOT NULL, tags TEXT NOT NULL,
      flds TEXT NOT NULL, sfld INTEGER NOT NULL, csum INTEGER NOT NULL,
      flags INTEGER NOT NULL, data TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE cards (
      id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL,
      ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL,
      type INTEGER NOT NULL, queue INTEGER NOT NULL, due INTEGER NOT NULL,
      ivl INTEGER NOT NULL, factor INTEGER NOT NULL, reps INTEGER NOT NULL,
      lapses INTEGER NOT NULL, left INTEGER NOT NULL, odue INTEGER NOT NULL,
      odid INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE revlog (
      id INTEGER PRIMARY KEY, cid INTEGER NOT NULL, usn INTEGER NOT NULL,
      ease INTEGER NOT NULL, ivl INTEGER NOT NULL, lastIvl INTEGER NOT NULL,
      factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL)''');

    await db.execute(
        'CREATE TABLE graves (usn INTEGER NOT NULL, oid INTEGER NOT NULL, type INTEGER NOT NULL)');

    final models = jsonEncode({
      '$modelId': {
        'id': '$modelId', 'name': 'English Reader', 'type': 0,
        'mod': now, 'usn': -1, 'sortf': 0, 'did': deckId,
        'tmpls': [{
          'name': 'Card 1', 'ord': 0,
          'qfmt': '<div style="font-size:2.2em;font-weight:bold;text-align:center;font-family:Georgia;">{{Word}}</div>',
          'afmt': '<div style="font-size:2.2em;font-weight:bold;text-align:center;font-family:Georgia;">{{Word}}</div><hr id=answer>'
              '{{#PartOfSpeech}}<div style="color:#666;font-style:italic;margin-bottom:8px;">({{PartOfSpeech}})</div>{{/PartOfSpeech}}'
              '<div style="font-size:1.1em;line-height:1.6;">{{Definition}}</div>'
              '{{#Sentence}}<div style="margin-top:12px;padding:10px 14px;background:#eef4ff;border-left:3px solid #007AFF;font-style:italic;color:#555;">"{{Sentence}}"</div>{{/Sentence}}'
              '{{#Source}}<div style="text-align:right;color:#aaa;font-size:0.85em;margin-top:8px;">— {{Source}}</div>{{/Source}}',
          'bqfmt': '', 'bafmt': '', 'did': null, 'bfont': '', 'bsize': 0,
        }],
        'flds': [
          {'name': 'Word',         'ord': 0, 'sticky': false, 'rtl': false, 'font': 'Georgia', 'size': 20},
          {'name': 'PartOfSpeech', 'ord': 1, 'sticky': false, 'rtl': false, 'font': 'Arial',   'size': 14},
          {'name': 'Definition',   'ord': 2, 'sticky': false, 'rtl': false, 'font': 'Arial',   'size': 14},
          {'name': 'Sentence',     'ord': 3, 'sticky': false, 'rtl': false, 'font': 'Arial',   'size': 14},
          {'name': 'Source',       'ord': 4, 'sticky': false, 'rtl': false, 'font': 'Arial',   'size': 12},
        ],
        'css': '.card{font-family:Arial,sans-serif;max-width:600px;margin:20px auto;padding:24px;}',
        'latexPre': '', 'latexPost': '', 'tags': [], 'vers': [],
      }
    });

    final decks = jsonEncode({
      '$deckId': {
        'id': deckId, 'name': 'English Book Reader',
        'extendRev': 50, 'usn': 0, 'collapsed': false,
        'newToday': [0, 0], 'timeToday': [0, 0], 'dyn': 0,
        'extendNew': 10, 'conf': 1, 'revToday': [0, 0],
        'lrnToday': [0, 0], 'mod': now, 'desc': '',
      }
    });

    await db.insert('col', {
      'id': 1, 'crt': now, 'mod': now, 'scm': now * 1000,
      'ver': 11, 'dty': 0, 'usn': 0, 'ls': 0,
      'conf': '{}', 'models': models, 'decks': decks,
      'dconf': '{"1":{"id":1,"mod":0,"name":"Default","usn":0,"maxTaken":60,"autoplay":true,"timer":0,"replayq":true,"new":{"bury":false,"delays":[1,10],"initialFactor":2500,"ints":[1,4,0],"order":1,"perDay":20,"separate":true},"lapse":{"delays":[10],"leechAction":1,"leechFails":8,"minInt":1,"mult":0},"rev":{"bury":false,"ease4":1.3,"fuzz":0.05,"ivlFct":1,"maxIvl":36500,"minSpace":1,"perDay":100}}}',
      'tags': '{}',
    });

    for (var i = 0; i < entries.length; i++) {
      final e      = entries[i];
      final noteId = now * 1000 + i;
      final cardId = noteId + 500000;
      final flds   = '${e.word}\x1f${e.partOfSpeech}\x1f${e.definition}\x1f${e.sentence}\x1f${e.source}';

      await db.insert('notes', {
        'id': noteId, 'guid': noteId.toRadixString(36),
        'mid': modelId, 'mod': now, 'usn': -1, 'tags': '',
        'flds': flds, 'sfld': 0,
        'csum': e.word.hashCode & 0xFFFFFFFF,
        'flags': 0, 'data': '',
      });
      await db.insert('cards', {
        'id': cardId, 'nid': noteId, 'did': deckId, 'ord': 0,
        'mod': now, 'usn': -1, 'type': 0, 'queue': 0,
        'due': i, 'ivl': 0, 'factor': 0, 'reps': 0,
        'lapses': 0, 'left': 0, 'odue': 0, 'odid': 0,
        'flags': 0, 'data': '',
      });
    }
  }
}
