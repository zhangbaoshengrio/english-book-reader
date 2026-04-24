import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sq;

/// MDict MDX v2 parser.
/// On first use, builds a SQLite word-index beside the .mdx file.
class MdxService {
  static const _idxSuffix = '.idx.db';

  // In-memory cache: "$mdxPath\x00$word" → HTML result (null = not found)
  static final _cache = <String, String?>{};
  static const _maxCache = 200;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Build a SQLite index for [mdxPath].
  /// Already-indexed files return immediately.
  /// [onProgress] receives (0‥1, statusText).
  static Future<int> buildIndex(
    String mdxPath,
    void Function(double, String) onProgress,
  ) async {
    final idxPath = mdxPath + _idxSuffix;
    final db = await _openIdxDb(idxPath);

    final existing = sq.Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM mdx_keys'));
    if ((existing ?? 0) > 0) {
      // Also verify meta is complete — a previous failed build may have left
      // words in the index but no rec_json / rec_start metadata.
      final metaCount = sq.Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM mdx_meta WHERE key = 'rec_json'"));
      if ((metaCount ?? 0) > 0) {
        await db.close();
        return existing!;
      }
      // Incomplete index — clear and rebuild.
      await db.delete('mdx_keys');
      await db.delete('mdx_meta');
    }

    final raf = await File(mdxPath).open();
    int total = 0;
    try {
      onProgress(0.0, '解析词典头...');

      // ── Header ──────────────────────────────────────────────────────────────
      final headerLenBytes = Uint8List.fromList(await raf.read(4));
      final headerLen = _u32be(headerLenBytes, 0);
      final headerRaw = Uint8List.fromList(await raf.read(headerLen));
      await raf.read(4); // checksum
      final headerXml = _utf16le(headerRaw);
      final encoding = _parseEncoding(headerXml);
      final encrypted = _parseEncrypted(headerXml);
      debugPrint('[MDX] encoding=$encoding encrypted=$encrypted');

      // ── Key section header (5 × int64 + checksum) ───────────────────────────
      onProgress(0.03, '读取索引...');
      final ksh = ByteData.sublistView(Uint8List.fromList(await raf.read(40)));
      final numKeyBlocks = ksh.getInt64(0, Endian.big);
      // [8] numEntries, [8] keyIdxDecompSz (ignored)
      final keyIdxSz = ksh.getInt64(24, Endian.big);
      // [8] keyBlocksTotalSz
      await raf.read(4); // checksum

      // ── Key index (lists compressed size of each key block) ─────────────────
      final keyIdxRaw = Uint8List.fromList(await raf.read(keyIdxSz));
      debugPrint('[MDX] keyIdxRaw len=${keyIdxRaw.length} numKeyBlocks=$numKeyBlocks');
      final keyIdx = _decompressBlock(keyIdxRaw, encrypted: encrypted);
      debugPrint('[MDX] keyIdx decompressed len=${keyIdx.length}');

      final kBlockSizes = <int>[];
      var ki = 0;
      for (var b = 0; b < numKeyBlocks; b++) {
        ki += 8; // numEntries
        final fsz = _u16be(keyIdx, ki); ki += 2;
        // +1 for null terminator (UTF-8: 1 byte, UTF-16: 2 bytes)
        ki += encoding == 'UTF-16' ? (fsz + 1) * 2 : fsz + 1;
        final lsz = _u16be(keyIdx, ki); ki += 2;
        ki += encoding == 'UTF-16' ? (lsz + 1) * 2 : lsz + 1;
        kBlockSizes.add(_i64be(keyIdx, ki)); ki += 8;
        ki += 8; // decompSz
      }

      // ── Read all key blocks → collect (word, recordOffset) ─────────────────
      onProgress(0.08, '提取词条...');
      final allKeys = <({String word, int offset})>[];

      for (var bi = 0; bi < kBlockSizes.length; bi++) {
        final raw = Uint8List.fromList(await raf.read(kBlockSizes[bi]));
        // Key blocks are NOT encrypted (only the key index is, for Encrypted=2)
        final blk = _decompressBlock(raw);
        var ep = 0;
        while (ep + 8 < blk.length) {
          final recOff = _i64be(blk, ep); ep += 8;
          String word;
          if (encoding == 'UTF-16') {
            final s = ep;
            while (ep + 1 < blk.length &&
                !(blk[ep] == 0 && blk[ep + 1] == 0)) { ep += 2; }
            word = _utf16le(blk.sublist(s, ep));
            ep += 2;
          } else {
            final s = ep;
            while (ep < blk.length && blk[ep] != 0) { ep++; }
            word = utf8.decode(blk.sublist(s, ep), allowMalformed: true);
            ep++;
          }
          if (word.isNotEmpty) allKeys.add((word: word.toLowerCase(), offset: recOff));
        }
        onProgress(0.08 + 0.55 * (bi + 1) / kBlockSizes.length,
            '读取词块 ${bi + 1}/${kBlockSizes.length}');
      }

      total = allKeys.length;
      onProgress(0.63, '建立索引 ($total 词)...');

      // ── Batch insert ─────────────────────────────────────────────────────────
      const bsz = 2000;
      for (var i = 0; i < allKeys.length; i += bsz) {
        final end = (i + bsz).clamp(0, allKeys.length);
        await db.transaction((t) async {
          final b = t.batch();
          for (var j = i; j < end; j++) {
            b.insert('mdx_keys', {
              'word': allKeys[j].word,
              'record_offset': allKeys[j].offset,
            });
          }
          await b.commit(noResult: true);
        });
        onProgress(0.63 + 0.27 * end / allKeys.length, '写入 $end/$total...');
      }

      // ── Record section header ────────────────────────────────────────────────
      final rsh = ByteData.sublistView(Uint8List.fromList(await raf.read(32)));
      final numRecBlocks = rsh.getInt64(0, Endian.big);
      // [8] numEntries, [8] indexSz, [8] blocksTotalSz

      final recMeta = <Map<String, int>>[];
      var cumDecomp = 0;
      for (var i = 0; i < numRecBlocks; i++) {
        final ri = ByteData.sublistView(Uint8List.fromList(await raf.read(16)));
        final cSz = ri.getInt64(0, Endian.big);
        final dSz = ri.getInt64(8, Endian.big);
        recMeta.add({'c': cSz, 'd': dSz, 'cum': cumDecomp});
        cumDecomp += dSz;
      }

      final recStart = await raf.position();
      await db.insert('mdx_meta', {'key': 'rec_json', 'value': jsonEncode(recMeta)});
      await db.insert('mdx_meta', {'key': 'rec_start', 'value': recStart.toString()});
      await db.execute('CREATE INDEX IF NOT EXISTS idx_word ON mdx_keys(word)');
      onProgress(1.0, '完成！');
    } catch (e, st) {
      debugPrint('[MDX] buildIndex ERROR: $e\n$st');
      rethrow;
    } finally {
      await raf.close();
      await db.close();
    }
    return total;
  }

  /// Look up [word] in the MDX file. Returns HTML/text definition or null.
  static Future<String?> lookup(String mdxPath, String word) async {
    final cacheKey = '$mdxPath\x00${word.toLowerCase()}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
    final idxPath = mdxPath + _idxSuffix;
    if (!File(idxPath).existsSync()) {
      debugPrint('[MDX] no idx file: $idxPath');
      return null;
    }

    final db = await sq.openDatabase(idxPath, readOnly: true);
    try {
      final total = sq.Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM mdx_keys'));
      final metaCount = sq.Sqflite.firstIntValue(
          await db.rawQuery("SELECT COUNT(*) FROM mdx_meta WHERE key='rec_json'"));
      debugPrint('[MDX] idx entries=$total meta=$metaCount word=$word');

      final rows = await db.query('mdx_keys',
          where: 'word = ?', whereArgs: [word.toLowerCase()]);
      if (rows.isEmpty) return null;

      final metaRows = await db.query('mdx_meta');
      final meta = {for (final r in metaRows) r['key'] as String: r['value'] as String};

      final recMeta = (jsonDecode(meta['rec_json']!) as List)
          .cast<Map<String, dynamic>>();
      final recStart = int.parse(meta['rec_start']!);

      // Fetch HTML for every matching entry and concatenate
      final raf = await File(mdxPath).open();
      final parts = <String>[];
      try {
        for (final row in rows) {
          final recOff = row['record_offset'] as int;

          // Find block containing recOff
          int bi = recMeta.length - 1;
          for (var i = 0; i < recMeta.length; i++) {
            final cum = recMeta[i]['cum'] as int;
            final d = recMeta[i]['d'] as int;
            if (cum + d > recOff) { bi = i; break; }
          }

          // File offset of the block
          var fileOff = recStart;
          for (var i = 0; i < bi; i++) { fileOff += recMeta[i]['c'] as int; }

          await raf.setPosition(fileOff);
          final raw = Uint8List.fromList(await raf.read(recMeta[bi]['c'] as int));
          final dec = _decompressBlock(raw);
          final localOff = recOff - (recMeta[bi]['cum'] as int);
          var end = localOff;
          while (end < dec.length && dec[end] != 0) { end++; }
          if (end > localOff) {
            parts.add(utf8.decode(dec.sublist(localOff, end), allowMalformed: true));
          }
        }
      } finally {
        await raf.close();
      }
      if (parts.isNotEmpty) {
        // Resolve @@@LINK= redirects (MDX convention for inflected forms)
        final resolved = <String>[];
        for (final part in parts) {
          final trimmed = part.trim();
          if (trimmed.startsWith('@@@LINK=')) {
            final target = trimmed.substring(8).trim();
            if (target.isNotEmpty && target.toLowerCase() != word.toLowerCase()) {
              final linked = await lookup(mdxPath, target);
              if (linked != null) resolved.add(linked);
            }
          } else {
            resolved.add(part);
          }
        }
        if (resolved.isNotEmpty) {
          // Use \x00 as entry separator — \n may appear inside HTML content
          final result = resolved.join('\x00');
          if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
          _cache[cacheKey] = result;
          return result;
        }
      }
    } finally {
      await db.close();
    }
    _cache[cacheKey] = null;
    return null;
    } catch (_) {
      return null;
    }
  }

  static bool isIndexed(String mdxPath) =>
      File(mdxPath + _idxSuffix).existsSync();

  // ── Binary helpers ─────────────────────────────────────────────────────────

  /// Decompress an MDX data block.
  /// If [encrypted] is true, applies MDX Encrypted=2 decryption before decompressing.
  static Uint8List _decompressBlock(Uint8List data, {bool encrypted = false}) {
    if (data.length < 4) return data;
    final type = data[0]; // first byte of 4-byte LE type indicator

    if (type == 0x02) {
      // Get payload (bytes after 8-byte header: type[4] + checksum[4])
      if (data.length <= 8) return Uint8List(0);
      final payload = encrypted ? _mdxDecrypt(data) : data.sublist(8);
      // Standard zlib
      try {
        return Uint8List.fromList(ZLibDecoder().convert(payload));
      } catch (_) {}
      // Raw deflate fallback (should not be needed after correct decryption)
      try {
        return Uint8List.fromList(ZLibDecoder(raw: true).convert(payload));
      } catch (_) {}
      debugPrint('[MDX] zlib decomp failed len=${data.length} encrypted=$encrypted');
      return Uint8List(0);
    }

    if (type == 0x00) {
      // No compression
      if (data.length > 8) return data.sublist(8);
      if (data.length > 4) return data.sublist(4);
      return data;
    }

    if (type == 0x01) {
      debugPrint('[MDX] LZO block unsupported');
      return Uint8List(0);
    }

    debugPrint('[MDX] unknown block type=0x${type.toRadixString(16)}');
    return Uint8List(0);
  }

  /// MDX Encrypted=2 block decryption.
  /// Input: full block bytes (type[4] + checksum[4] + encrypted_payload).
  /// Returns: decrypted payload (ready for zlib).
  static Uint8List _mdxDecrypt(Uint8List block) {
    // Key = RIPEMD-128(checksum[4] + pack('<L', 0x3695))
    // The constant 0x3695 stored as little-endian uint32 = \x95\x36\x00\x00
    final keyInput = Uint8List(8)
      ..[0] = block[4] ..[1] = block[5] ..[2] = block[6] ..[3] = block[7]
      ..[4] = 0x95     ..[5] = 0x36     ..[6] = 0x00     ..[7] = 0x00;
    final key = _ripemd128(keyInput);

    final payload = block.sublist(8);
    final result = Uint8List(payload.length);
    var prev = 0x36;
    for (var i = 0; i < payload.length; i++) {
      final b = payload[i];
      var t = ((b >> 4) | ((b << 4) & 0xFF)) & 0xFF;
      t = (t ^ prev ^ (i & 0xFF) ^ key[i % 16]) & 0xFF;
      prev = b;
      result[i] = t;
    }
    return result;
  }

  /// RIPEMD-128 hash function. Returns 16-byte digest.
  static Uint8List _ripemd128(Uint8List data) {
    // Word indices for left and right rounds
    const rl = [
      0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
      7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
      3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
      1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
    ];
    const sl = [
      11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
      7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
      11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
      11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
    ];
    const rr = [
      5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
      6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
      15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
      8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
    ];
    const sr = [
      8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
      9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
      9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
      15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
    ];
    const kl = [0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC];
    const kr = [0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x00000000];

    var h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476];

    // MD-padding: append 0x80, zeros, then 64-bit message length (LE)
    final padLen = ((data.length + 9 + 63) ~/ 64) * 64;
    final msg = Uint8List(padLen);
    msg.setAll(0, data);
    msg[data.length] = 0x80;
    ByteData.sublistView(msg, padLen - 8)
        .setUint64(0, data.length * 8, Endian.little);

    for (var off = 0; off < msg.length; off += 64) {
      final w = List<int>.generate(16, (i) =>
          ByteData.sublistView(msg, off + i * 4, off + i * 4 + 4)
              .getUint32(0, Endian.little));

      var al = h[0], bl = h[1], cl = h[2], dl = h[3];
      var ar = h[0], br = h[1], cr = h[2], dr = h[3];

      int rol32(int x, int n) =>
          ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

      for (var j = 0; j < 64; j++) {
        final round = j >> 4;
        final int fl, fr;
        switch (round) {
          case 0:
            fl = bl ^ cl ^ dl;
            fr = (br & dr) | (cr & (~dr & 0xFFFFFFFF));
            break;
          case 1:
            fl = (bl & cl) | ((~bl & 0xFFFFFFFF) & dl);
            fr = (br | (~cr & 0xFFFFFFFF)) ^ dr;
            break;
          case 2:
            fl = (bl | (~cl & 0xFFFFFFFF)) ^ dl;
            fr = (br & cr) | ((~br & 0xFFFFFFFF) & dr);
            break;
          default:
            fl = (bl & dl) | (cl & (~dl & 0xFFFFFFFF));
            fr = br ^ cr ^ dr;
        }

        var tl = (al + fl + w[rl[j]] + kl[round]) & 0xFFFFFFFF;
        tl = rol32(tl, sl[j]);
        al = dl; dl = cl; cl = bl; bl = tl;

        var tr = (ar + fr + w[rr[j]] + kr[round]) & 0xFFFFFFFF;
        tr = rol32(tr, sr[j]);
        ar = dr; dr = cr; cr = br; br = tr;
      }

      final t = (h[1] + cl + dr) & 0xFFFFFFFF;
      h[1] = (h[2] + dl + ar) & 0xFFFFFFFF;
      h[2] = (h[3] + al + br) & 0xFFFFFFFF;
      h[3] = (h[0] + bl + cr) & 0xFFFFFFFF;
      h[0] = t;
    }

    final result = Uint8List(16);
    final bd = ByteData.sublistView(result);
    for (var i = 0; i < 4; i++) bd.setUint32(i * 4, h[i], Endian.little);
    return result;
  }

  static String _utf16le(Uint8List b) {
    final codes = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      final u = b[i] | (b[i + 1] << 8);
      if (u == 0) break;
      codes.add(u);
    }
    return String.fromCharCodes(codes);
  }

  static String _parseEncoding(String xml) {
    final m = RegExp(r'Encoding="([^"]*)"', caseSensitive: false).firstMatch(xml);
    if (m != null) {
      final e = m.group(1)!.toUpperCase();
      if (e.contains('16')) return 'UTF-16';
    }
    return 'UTF-8';
  }

  /// Returns true if the MDX file uses Encrypted=2 (key block encryption).
  static bool _parseEncrypted(String xml) {
    final m = RegExp(r'Encrypted="([^"]*)"', caseSensitive: false).firstMatch(xml);
    if (m != null) {
      final v = m.group(1)!.trim();
      return v == '2' || v == '3';
    }
    return false;
  }

  static int _i64be(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 8).getInt64(0, Endian.big);
  static int _u32be(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 4).getUint32(0, Endian.big);
  static int _u16be(Uint8List b, int off) =>
      ByteData.sublistView(b, off, off + 2).getUint16(0, Endian.big);

  static Future<sq.Database> _openIdxDb(String path) => sq.openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE mdx_keys (word TEXT NOT NULL, record_offset INTEGER NOT NULL)');
          await db.execute(
              'CREATE TABLE mdx_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        },
      );
}
