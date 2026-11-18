import 'package:flutter/material.dart';

import 'tokens.dart';

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
  static const Color lightSub = Color(0xFF666A6E);

  static const Color darkBg = Color(0xFF111319);
  static const Color darkCard = Color(0xFF1C1D21);
  static const Color darkLine = Color(0xFF2B2D32);
  static const Color darkText = Color(0xFFEDEEF0);

  /// 暗色次要文字。
  ///
  /// 注意这里不是上一版的 `#A8ABAE` —— 那个值是按手挑的紫灰色域标定的，
  /// 而真实渲染出来的暗色玻璃表面是**冷蓝到紫调**的一整片色带
  /// （见 `docs/preview/12-dark-settings.png` 采样结果），在那种表面上
  /// `#A8ABAE` 只有 3.12:1，达不到 AA。改成按真实色域重新标定的
  /// `#D1D7DB`（最差 4.80:1）。
  static const Color darkSub = Color(0xFFD1D7DB);
}

class AppTheme {
  AppTheme._();

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.darkBg : AppColors.lightBg;
    final card = dark ? AppColors.darkCard : AppColors.lightCard;
    final line = dark ? AppColors.darkLine : AppColors.lightLine;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    // 次要文字直接用标定过的二级色，不再用 darkSub/lightSub 的旧值。
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
          fontSize: AppFontSize.appBar,
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
        labelStyle: TextStyle(color: text, fontSize: AppFontSize.body),
        secondaryLabelStyle:
            const TextStyle(color: AppColors.pink, fontSize: AppFontSize.body),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: dark ? Colors.white12 : Colors.white70),
        brightness: brightness,
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
            color: text,
            fontSize: AppFontSize.headline,
            fontWeight: FontWeight.w700,
            height: 1.25),
        titleLarge: TextStyle(
            color: text,
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w700,
            height: 1.3),
        titleMedium: TextStyle(
            color: text,
            fontSize: AppFontSize.bodyLarge,
            fontWeight: FontWeight.w600,
            height: 1.35),
        bodyLarge: TextStyle(color: text, fontSize: AppFontSize.bodyLarge, height: 1.5),
        bodyMedium: TextStyle(color: text, fontSize: AppFontSize.body, height: 1.45),
        bodySmall: TextStyle(color: sub, fontSize: AppFontSize.small, height: 1.4),
        labelSmall: TextStyle(color: sub, fontSize: AppFontSize.caption),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        hintStyle: TextStyle(color: sub, fontSize: AppFontSize.body),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: dark ? Colors.white24 : Colors.white),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: dark ? Colors.white24 : Colors.white),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
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
      // 以下一组是上一版完全缺失的：Material 内置控件的默认造型全是
      // Material 2/3 的老样式，跟这套玻璃视觉对不上（开关是方角小块、
      // 滑块轨道太细、按钮没有自己的圆角）。
      //
      // 注意：工程锁在 Flutter 3.0，`FilledButton` 是 Material 3 才引入的，
      // 这里只能用 3.0 里存在的 `raisedButton` / `outlinedButton` / `textButton`。
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.disabled)) {
            return dark ? const Color(0xFF6A6F76) : const Color(0xFFB9BEC5);
          }
          return Colors.white;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.disabled)) {
            return dark ? Colors.white10 : Colors.black12;
          }
          if (states.contains(MaterialState.selected)) {
            return AppColors.pink;
          }
          return dark ? Colors.white24 : Colors.black26;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.pink,
        inactiveTrackColor: dark ? Colors.white12 : Colors.black12,
        thumbColor: AppColors.pink,
        overlayColor: AppColors.pink.withOpacity(0.12),
        trackHeight: 4,
      ),
      // 注意：工程锁在 Flutter 3.0 —— 这一版刚好把 `RaisedButton` 移除了
      //（3.0 是它的最后一个版本），`FilledButton` 又是 Material 3 才引入的，
      // 所以只能靠 `buttonTheme` 这个总闸来统一按钮造型。
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textTheme: ButtonTextTheme.primary,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return sub;
            }
            return text;
          }),
          side: MaterialStateProperty.all<BorderSide>(
            BorderSide(color: dark ? Colors.white24 : Colors.black26),
          ),
          textStyle: MaterialStateProperty.all<TextStyle>(const TextStyle(
              fontSize: AppFontSize.body, fontWeight: FontWeight.w600)),
          padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          shape: MaterialStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return sub;
            }
            return AppColors.pink;
          }),
          textStyle: MaterialStateProperty.all<TextStyle>(const TextStyle(
              fontSize: AppFontSize.body, fontWeight: FontWeight.w600)),
          shape: MaterialStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xF0333540) : const Color(0xF22A2C38),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: AppFontSize.caption),
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
