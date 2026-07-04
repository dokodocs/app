import 'package:flutter/material.dart';

/// Material 3 theme shared across Android/iOS (spec Section 6: "Material 3
/// on Android, Cupertino-appropriate navigation feel on iOS, shared design
/// language between them"). Cupertino-specific navigation transitions are
/// introduced once there's more than one screen to transition between
/// (Phase 1) — Phase 0 ships a single screen.
class AppTheme {
  AppTheme._();

  static const _seedColor = Color(0xFF2E7D6B);

  // Toned down from Material 3's defaults per user feedback that text felt
  // too big/heavy-handed across the app — smaller sizes *and* nothing
  // above medium weight (w500), so headings read as calm emphasis rather
  // than shouting.
  static const _textTheme = TextTheme(
    headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
    headlineSmall: TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
    titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
  );

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      textTheme: _textTheme,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      textTheme: _textTheme,
    );
  }
}
