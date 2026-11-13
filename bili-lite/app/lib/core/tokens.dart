import 'package:flutter/material.dart';

import 'theme.dart';

/// 全局设计令牌。
///
/// 背景：这套 App 的视觉是「玻璃」，但玻璃不等于没有规范。重构前颜色、字号、
/// 圆角散落在 30+ 个文件里，同一语义出现多个色值（例如「次要文字」在深色
/// 模式下有 3 个不同写法），导致同一段文字在不同页面明暗表现不一致。
///
/// 这里把「语义 → 取值」的映射集中到一处，页面只引用语义名。
/// 后续调整主题只需改这一个文件。

/// 状态色：成功 / 警告 / 危险 / 中性。
/// 之前散落在 format.dart、shell_page.dart、settings_page.dart、account_card.dart
/// 共 4 个文件里的 0xFF34B27B / 0xFFE9A23B / 0xFFD98032 / 0xFF8B8F98 全部收敛到这里。
class AppStatus {
  AppStatus._();

  /// 连接正常、实时数据可用。
  static const Color success = Color(0xFF34B27B);

  /// 缓存可用但非实时。
  static const Color warning = Color(0xFFE9A23B);

  /// 需要用户注意（凭证缺失、授权失败、已降级）。
  static const Color danger = Color(0xFFD98032);

  /// 中性：离线、不可用。
  static const Color neutral = Color(0xFF8B8F98);
}

/// 字体尺寸阶梯。
///
/// 重构前同一层级出现过 11 / 11.5 / 12 / 12.5 / 13 / 13.5 / 14 / 15 / 15.5 /
/// 16 / 18 / 19 等十几种数值。这里固定成 8 级。
class AppFontSize {
  AppFontSize._();

  /// 10.5 —— 徽标、极次要信息
  static const double micro = 10.5;

  /// 11 —— 辅助说明
  static const double caption = 11;

  /// 12 —— 次要信息
  static const double small = 12;

  /// 13 —— 正文次级、按钮文字
  static const double body = 13;

  /// 14 —— 正文
  static const double bodyLarge = 14;

  /// 16 —— 卡片标题
  static const double title = 16;

  /// 18 —— 页面主标题
  static const double headline = 18;

  /// 19 —— AppBar 标题
  static const double appBar = 19;
}

/// 圆角阶梯。
///
/// 重构前同一含义的容器出现过 8 / 9 / 10 / 11 / 12 / 13 / 14 / 16 / 18 / 20 / 22 / 26
/// 等十几种数值，玻璃面板与普通容器的圆角也没有明确区分。
class AppRadius {
  AppRadius._();

  /// 小徽章、标签
  static const double chip = 10;

  /// 按钮、内嵌小卡
  static const double control = 14;

  /// 常规容器（卡片、面板）
  static const double panel = 20;

  /// 大容器（对话框、浮层）
  static const double sheet = 22;

  /// 导航栏、悬浮 dock
  static const double dock = 26;

  /// 胶囊
  static const double pill = 999;
}

/// 间距阶梯（4 的倍数，便于对齐）。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// BuildContext 扩展：把「当前主题下的次要文字色」等常用取色收敛成一行调用。
///
/// 重构前每个文件都写着 `Theme.of(context).brightness == Brightness.dark
/// ? AppColors.darkSub : AppColors.lightSub`，其中好几处**漏掉了深色分支**
/// （详见重构说明 §2.3），导致深色模式下出现浅灰文字。
extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// 次要文字色（说明、计数、辅助标签）。
  Color get subTextColor => isDark ? AppColors.darkSub : AppColors.lightSub;

  /// 主文字色。
  Color get primaryTextColor =>
      isDark ? AppColors.darkText : AppColors.lightText;
}
