import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'voice_engine_service.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;
  static double _speed = 0.75;

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
    _ready = false; // force re-init with new speed
  }

  static Future<void> speak(String text) async {
    // Dispatch to active voice engine
    final engine = await VoiceEngineService.getActiveEngine();
    if (engine != null) {
      if (engine.type == VoiceEngineType.builtinTts) {
        // Use engine's stored speed
        _speed = engine.speed;
        _ready = false;
      } else {
        final bytes = await VoiceEngineService.fetchAudio(text, engine);
        if (bytes != null && bytes.isNotEmpty) {
          await _playBytes(bytes);
          return;
        }
        // Fall through to builtin on failure
      }
    }
    await _speakBuiltin(text);
  }

  static Future<void> _speakBuiltin(String text) async {
    await _init();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Play raw audio bytes directly (for preview use).
  static Future<void> playBytes(List<int> bytes) => _playBytes(bytes);

  static Future<void> _playBytes(List<int> bytes) async {
    String? path;
    try {
      path = await VoiceEngineService.saveTempAudio(bytes, 'mp3');
      if (path == null) return;
      await _tts.stop();
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      // ignore playback errors
    } finally {
      // Clean up temp file after a delay
      if (path != null) {
        final filePath = path;
        Future.delayed(const Duration(seconds: 30), () {
          try { File(filePath).deleteSync(); } catch (_) {}
        });
      }
    }
  }

  /// Speak text using the dedicated AI-result voice engine.
  static Future<void> speakAi(String text) async {
    final engine = await VoiceEngineService.getAiEngine();
    if (engine != null) {
      if (engine.type == VoiceEngineType.builtinTts) {
        _speed = engine.speed;
        _ready = false;
      } else {
        final bytes = await VoiceEngineService.fetchAudio(text, engine);
        if (bytes != null && bytes.isNotEmpty) {
          await _playBytes(bytes);
          return;
        }
        // Fall through to builtin on failure
      }
    }
    await _speakBuiltin(text);
  }

  static Future<void> stop() async {
    await _tts.stop();
    await _player.stop();
  }
}
