import 'package:flutter/material.dart';

/// 视觉基调：低饱和极光背景、半透明玻璃容器、克制的粉色点缀。
class AppColors {
  AppColors._();

  static const Color pink = Color(0xFFFB7299);
  static const Color pinkSoft = Color(0xFFFFF0F4);
  static const Color blue = Color(0xFF00AEEC);

  static const Color lightBg = Color(0xFFF4F6FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightLine = Color(0xFFECEEF1);
  static const Color lightText = Color(0xFF18191C);
  static const Color lightSub = Color(0xFF7E8490);

  static const Color darkBg = Color(0xFF111319);
  static const Color darkCard = Color(0xFF1C1D21);
  static const Color darkLine = Color(0xFF2B2D32);
  static const Color darkText = Color(0xFFEDEEF0);
  static const Color darkSub = Color(0xFF9499A3);
}

class AppTheme {
  AppTheme._();

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.darkBg : AppColors.lightBg;
    final card = dark ? AppColors.darkCard : AppColors.lightCard;
    final line = dark ? AppColors.darkLine : AppColors.lightLine;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    final scheme = ColorScheme.fromSwatch(
      brightness: brightness,
      primarySwatch: _pinkSwatch,
      accentColor: AppColors.pink,
      cardColor: card,
      backgroundColor: bg,
    );

    return ThemeData(
      brightness: brightness,
      primaryColor: AppColors.pink,
      colorScheme: scheme,
      // 关键：让 Scaffold 透明，才能看到 app.dart 里铺的极光背景，
      // 玻璃面板叠在其上形成透射与折射。
      scaffoldBackgroundColor: Colors.transparent,
      cardColor: card,
      canvasColor: Colors.transparent,
      dividerColor: dark ? Colors.white12 : Colors.black12,
      splashColor: AppColors.pink.withOpacity(0.06),
      highlightColor: AppColors.pink.withOpacity(0.04),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.pink,
        unselectedItemColor: sub,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: const IconThemeData(color: AppColors.pink),
        unselectedIconTheme: IconThemeData(color: sub),
        selectedLabelTextStyle: const TextStyle(
            color: AppColors.pink, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: sub, fontSize: 12),
        groupAlignment: -0.85,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? Colors.white10 : Colors.white70,
        selectedColor: AppColors.pink.withOpacity(0.12),
        disabledColor: line,
        labelStyle: TextStyle(color: text, fontSize: 13),
        secondaryLabelStyle:
            const TextStyle(color: AppColors.pink, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: dark ? Colors.white12 : Colors.white70),
        brightness: brightness,
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(color: text, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: sub),
        labelSmall: TextStyle(color: sub),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        hintStyle: TextStyle(color: sub),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: dark ? Colors.white24 : Colors.white),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: dark ? Colors.white24 : Colors.white),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.pink, width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(
          color: dark ? Colors.white12 : Colors.black12, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: sub, size: 20),
      dialogTheme: DialogTheme(
        backgroundColor: dark ? const Color(0xF01F212C) : const Color(0xF8FFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xF02A2C38) : const Color(0xF5FFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: TextStyle(color: text, fontSize: 13),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.pink,
      ),
    );
  }

  static const MaterialColor _pinkSwatch = MaterialColor(
    0xFFFB7299,
    <int, Color>{
      50: Color(0xFFFFF0F4),
      100: Color(0xFFFFD9E4),
      200: Color(0xFFFFB3C9),
      300: Color(0xFFFF8CAE),
      400: Color(0xFFFB7299),
      500: Color(0xFFFB7299),
      600: Color(0xFFE85F88),
      700: Color(0xFFD14A75),
      800: Color(0xFFB93663),
      900: Color(0xFF941E4C),
    },
  );
}
