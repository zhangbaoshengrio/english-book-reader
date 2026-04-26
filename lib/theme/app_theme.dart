import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // iOS-style colour tokens
  static const Color primary       = Color(0xFF007AFF);
  static const Color background    = Color(0xFFFFFFFF);
  static const Color groupedBg     = Color(0xFFF2F2F7);
  static const Color cardBg        = Color(0xFFFFFFFF);
  static const Color separator     = Color(0xFFC6C6C8);
  static const Color textPrimary   = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF6C6C70);
  static const Color textTertiary  = Color(0xFFAEAEB2);
  static const Color success       = Color(0xFF34C759);
  static const Color danger        = Color(0xFFFF3B30);
  static const Color readerBg      = Color(0xFFFDF8F0); // warm paper
  static const Color readerBgGreen = Color(0xFFC7EDCC); // eye-care green

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      surface: cardBg,
    ),
    scaffoldBackgroundColor: groupedBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cardBg,
      surfaceTintColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge:  TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: textPrimary),
      titleLarge:     TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium:    TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge:      TextStyle(fontSize: 17, color: textPrimary),
      bodyMedium:     TextStyle(fontSize: 15, color: textPrimary),
      bodySmall:      TextStyle(fontSize: 13, color: textSecondary),
      labelSmall:     TextStyle(fontSize: 11, color: textTertiary, letterSpacing: 0.5),
    ),
    dividerTheme: const DividerThemeData(color: separator, thickness: 0.5, space: 0),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}
