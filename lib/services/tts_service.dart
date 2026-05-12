import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'voice_engine_service.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;
  static double _speed = 0.75;
  static bool _stopRequested = false;

  // ── Audio cache ────────────────────────────────────────────────────────────
  static final Map<String, List<int>> _audioCache = {};
  static const _maxCacheEntries = 120;

  static String _cacheKey(String text, VoiceEngine engine) =>
      '${engine.id}|${engine.voiceParam}|${engine.speed}|$text';

  static Future<List<int>?> _fetchWithCache(String text, VoiceEngine engine) async {
    final key = _cacheKey(text, engine);
    final cached = _audioCache[key];
    if (cached != null) return cached;
    final bytes = await VoiceEngineService.fetchAudio(text, engine);
    if (bytes != null && bytes.isNotEmpty) {
      if (_audioCache.length >= _maxCacheEntries) {
        final keys = _audioCache.keys.take(_maxCacheEntries ~/ 2).toList();
        for (final k in keys) _audioCache.remove(k);
      }
      _audioCache[key] = bytes;
    }
    return bytes;
  }

  static void clearCache() => _audioCache.clear();

  static Future<void> _init() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_speed);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  static Future<void> setSpeed(double speed) async {
    _speed = speed;
    _ready = false;
  }

  /// Split long text into sentence-level chunks ≤ maxLen chars.
  static List<String> _splitChunks(String text, {int maxLen = 300}) {
    if (text.length <= maxLen) return [text];
    final chunks = <String>[];
    final sentences = text.split(RegExp(r'(?<=[.!?。！？])\s+'));
    var buf = '';
    for (final s in sentences) {
      if (buf.isEmpty) {
        buf = s;
      } else if (buf.length + 1 + s.length <= maxLen) {
        buf += ' $s';
      } else {
        if (buf.isNotEmpty) chunks.add(buf.trim());
        buf = s;
      }
    }
    if (buf.isNotEmpty) chunks.add(buf.trim());
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  static Future<void> speak(String text) async {
    _stopRequested = false;
    final engine = await VoiceEngineService.getActiveEngine();
    if (engine != null) {
      if (engine.type == VoiceEngineType.builtinTts) {
        _speed = engine.speed;
        _ready = false;
      } else {
        try {
          final bytes = await _fetchWithCache(text, engine);
          if (bytes != null && bytes.isNotEmpty) {
            await _playBytes(bytes);
            return;
          }
        } catch (_) {}
      }
    }
    await _speakBuiltin(text);
  }

  static Future<void> _speakBuiltin(String text) async {
    await _init();
    await _tts.stop();
    await _tts.speak(text);
  }

  static Future<void> playBytes(List<int> bytes) => _playBytes(bytes);

  /// Play audio bytes. For single-shot use (non-sequential), fire-and-forget.
  /// For sequential chunk playback, waits via onPlayerComplete with timeout.
  static Future<void> _playBytes(List<int> bytes, {bool waitForComplete = false}) async {
    String? path;
    try {
      path = await VoiceEngineService.saveTempAudio(bytes, 'mp3');
      if (path == null) return;
      await _tts.stop();
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      if (waitForComplete) {
        // Estimate duration from file size: mp3 at 24kbps ≈ 3000 bytes/sec
        final estimatedMs = ((bytes.length / 3000) * 1000).round().clamp(1000, 120000);
        await _player.onPlayerComplete.first
            .timeout(Duration(milliseconds: estimatedMs + 5000));
      }
    } catch (_) {
      // ignore
    } finally {
      if (path != null) {
        final filePath = path;
        Future.delayed(const Duration(seconds: 30), () {
          try { File(filePath).deleteSync(); } catch (_) {}
        });
      }
    }
  }

  /// Speak using the AI-result voice engine, split into chunks for long text.
  static Future<void> speakAi(String text) async {
    _stopRequested = false;
    final engine = await VoiceEngineService.getAiEngine();
    if (engine != null && engine.type != VoiceEngineType.builtinTts) {
      final chunks = _splitChunks(text, maxLen: 300);
      final isMultiChunk = chunks.length > 1;
      for (final chunk in chunks) {
        if (_stopRequested) return;
        final bytes = await _fetchWithCache(chunk, engine);
        if (_stopRequested) return;
        if (bytes != null && bytes.isNotEmpty) {
          // Wait between chunks so they play sequentially
          await _playBytes(bytes, waitForComplete: isMultiChunk);
        }
      }
      return;
    }
    if (engine != null) {
      _speed = engine.speed;
      _ready = false;
    }
    await _speakBuiltin(text);
  }

  static Future<void> stop() async {
    _stopRequested = true;
    await _tts.stop();
    await _player.stop();
  }
}
