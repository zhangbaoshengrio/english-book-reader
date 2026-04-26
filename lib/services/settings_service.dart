import 'package:shared_preferences/shared_preferences.dart';

class ReaderTheme {
  static const paper = 'paper';
  static const white = 'white';
  static const dark  = 'dark';
  static const green = 'green';
}

class PageTurnStyle {
  static const scroll = 'scroll'; // vertical scroll + prev/next buttons
  static const swipe  = 'swipe';  // horizontal swipe gesture
}

class SettingsService {
  static const _autoSpeakKey     = 'auto_speak';
  static const _fontSizeKey      = 'font_size';
  static const _lineHeightKey    = 'line_height';
  static const _themeKey         = 'reader_theme';
  static const _fontFamilyKey    = 'font_family';
  static const _ttsSpeedKey      = 'tts_speed';
  static const _marginKey        = 'reader_margin';
  static const _pageTurnStyleKey = 'page_turn_style';

  // Translation
  static const _autoTranslateKey            = 'auto_translate_on_select';
  static const _translationEngineKey        = 'translation_engine';
  static const _customTranslationNameKey    = 'custom_translation_name';
  static const _customTranslationUrlKey     = 'custom_translation_url';
  static const _customTranslationJsonPathKey = 'custom_translation_json_path';

  // ── Auto-speak ────────────────────────────────────────────────────────────
  static Future<bool> getAutoSpeak() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_autoSpeakKey) ?? false;
  }
  static Future<void> setAutoSpeak(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_autoSpeakKey, v);
  }

  // ── Font size (14–26) ────────────────────────────────────────────────────
  static Future<double> getFontSize() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_fontSizeKey) ?? 18.0;
  }
  static Future<void> setFontSize(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_fontSizeKey, v);
  }

  // ── Line height (1.4–2.4) ────────────────────────────────────────────────
  static Future<double> getLineHeight() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_lineHeightKey) ?? 1.9;
  }
  static Future<void> setLineHeight(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_lineHeightKey, v);
  }

  // ── Reader theme ──────────────────────────────────────────────────────────
  static Future<String> getTheme() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_themeKey) ?? ReaderTheme.paper;
  }
  static Future<void> setTheme(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_themeKey, v);
  }

  // ── Font family ───────────────────────────────────────────────────────────
  static Future<String> getFontFamily() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_fontFamilyKey) ?? 'Georgia';
  }
  static Future<void> setFontFamily(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_fontFamilyKey, v);
  }

  // ── TTS speed (0.3–1.5) ──────────────────────────────────────────────────
  static Future<double> getTtsSpeed() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_ttsSpeedKey) ?? 0.75;
  }
  static Future<void> setTtsSpeed(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_ttsSpeedKey, v);
  }

  // ── Margin / horizontal padding (8–40) ───────────────────────────────────
  static Future<double> getMargin() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_marginKey) ?? 22.0;
  }
  static Future<void> setMargin(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_marginKey, v);
  }

  // ── Page turn style ───────────────────────────────────────────────────────
  static Future<String> getPageTurnStyle() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_pageTurnStyleKey) ?? PageTurnStyle.swipe;
  }
  static Future<void> setPageTurnStyle(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_pageTurnStyleKey, v);
  }

  // ── Translation ───────────────────────────────────────────────────────────
  static Future<bool> getAutoTranslate() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_autoTranslateKey) ?? true; // default ON
  }
  static Future<void> setAutoTranslate(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_autoTranslateKey, v);
  }

  static Future<String> getTranslationEngine() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_translationEngineKey) ?? 'google';
  }
  static Future<void> setTranslationEngine(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_translationEngineKey, v);
  }

  static Future<String> getCustomTranslationName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_customTranslationNameKey) ?? '';
  }
  static Future<void> setCustomTranslationName(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_customTranslationNameKey, v);
  }

  static Future<String> getCustomTranslationUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_customTranslationUrlKey) ?? '';
  }
  static Future<void> setCustomTranslationUrl(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_customTranslationUrlKey, v);
  }

  static Future<String> getCustomTranslationJsonPath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_customTranslationJsonPathKey) ?? '';
  }
  static Future<void> setCustomTranslationJsonPath(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_customTranslationJsonPathKey, v);
  }

  // ── Per-book scroll offset (for continuous scroll mode) ───────────────────
  static Future<double> getScrollOffset(int bookId) async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble('scroll_offset_$bookId') ?? 0.0;
  }
  static Future<void> setScrollOffset(int bookId, double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('scroll_offset_$bookId', v);
  }
}
