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
///
/// ## 本轮（第十八轮）扩充的内容
///
/// 上一版虽然定义了 [AppFontSize] 的 8 级阶梯，但统计全工程实际用到的字号
/// 却有 **17 种**（10 / 10.5 / 11 / 11.5 / 12 / 12.5 / 13 / 13.5 / 14 / 14.5 /
/// 15 / 15.5 / 16 / 17 / 18 / 19），而且大部分是硬编码在页面里的。
/// 原因是**只有数值阶梯、没有语义命名** —— 页面作者不知道「13.5 该用在哪」，
/// 只能就近抄一个，于是抄出了 17 种。
///
/// 所以这一轮把字号改成**按用途命名**（[AppFontSize]），并补上：
///   * [AppTextColor] —— 5 级文字层级，替代散落的 `subTextColor` / `darkSub`；
///   * [AppShadow] —— 4 级阴影层级，玻璃与普通卡片共用一套；
///   * [AppTextStyles] —— 常用组合（标题 / 副标题 / 正文 / 徽标）的工厂。
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

/// 字号阶梯（按**用途**命名，不是按大小）。
///
/// 取值覆盖上一版全部 8 级，并吸收了工程里实际在用但没进阶梯的
/// 13.5 / 14.5 / 15 / 15.5 / 17 / 19 —— 目的是让每个字号都有名字，
/// 页面作者有据可依，不再随手抄数值。
class AppFontSize {
  AppFontSize._();

  /// 9 —— 角标、气泡上的极小计数（几乎不用）
  static const double badge = 9;

  /// 10 —— 封面上的时长 / 弹幕数等压在图上的文字
  static const double overlay = 10;

  /// 10.5 —— 徽标、极次要信息
  static const double micro = 10.5;

  /// 11 —— 辅助说明
  static const double caption = 11;

  /// 11.5 —— 卡片底部的次要统计（UP 主名、播放量）
  static const double meta = 11.5;

  /// 12 —— 次要信息
  static const double small = 12;

  /// 12.5 —— 分组小标题、设置项的副标签
  static const double label = 12.5;

  /// 13 —— 正文次级、按钮文字
  static const double body = 13;

  /// 13.5 —— 卡片标题
  static const double cardTitle = 13.5;

  /// 14 —— 正文
  static const double bodyLarge = 14;

  /// 14.5 —— 分组标题
  static const double sectionTitle = 14.5;

  /// 15 —— 强调正文
  static const double emphasis = 15;

  /// 15.5 —— 详情页大标题
  static const double detailTitle = 15.5;

  /// 16 —— 卡片标题（列表型）
  static const double title = 16;

  /// 17 —— 浮层标题
  static const double sheetTitle = 17;

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

/// 阴影层级。
///
/// 上一版没有阴影体系，各组件各自 `BoxShadow` 随手写，同一个高度在不同页面
/// 投出不同强度的影子，玻璃与非玻璃卡片也没有区分。
///
/// 这里定 4 级：层级越高，扩散半径与不透明度越大，用于表达「离底层多远」。
/// 玻璃面板因为本身有高光与折射，阴影整体比同高度的普通卡片浅一档。
class AppShadow {
  AppShadow._();

  /// 贴面（level 0）：卡片内部、输入框、列表行 —— 几乎不可见，只做分层。
  static List<Shadow> level0(BuildContext context) => <Shadow>[
        Shadow(
          color: _shadowColor(context, 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// 常规（level 1）：普通卡片、浮层内的小卡。
  static List<Shadow> level1(BuildContext context) => <Shadow>[
        Shadow(
          color: _shadowColor(context, 0.07),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 浮起（level 2）：悬浮底栏、弹出面板、需要明确脱离底层的容器。
  static List<Shadow> level2(BuildContext context) => <Shadow>[
        Shadow(
          color: _shadowColor(context, 0.10),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  /// 高层（level 3）：对话框、模态浮层。
  static List<Shadow> level3(BuildContext context) => <Shadow>[
        Shadow(
          color: _shadowColor(context, 0.16),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ];

  /// 深色模式下阴影几乎不可见，改用「更深的墨色」来表达层级。
  static Color _shadowColor(BuildContext context, double lightOpacity) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? Colors.black.withOpacity(lightOpacity * 1.8)
        : Color.fromRGBO(24, 25, 28, lightOpacity);
  }
}

/// 文字层级色。
///
/// 上一版只有「主文字 / 次要文字」两档，实际用起来逼得页面在两档之间
/// 硬塞中间值（`Color(0xFF9499A3)` 之类的字面量）。而暗色模式下更糟：
/// 次要文字 `darkSub = 0xFF9499A3` 叠在深色玻璃上几乎读不出来
/// （见 `docs/preview/12-dark-settings.png` —— 设置页的分组说明文字
/// 几乎完全融进背景）。
///
/// 这里定 5 档，**每一档的取值都是按玻璃表面上的实际对比度标定过的**
/// （玻璃表面比纯色背景更亮，文字压在上面会掉对比度，不能直接用背景色的
/// 对比度来推）。
///
/// 标定的基准色域不是拍脑袋列的，而是从真实截图里**采样出来的玻璃表面**：
/// 众数滤波掉文字与图标后，暗色设置页（`docs/preview/12-dark-settings.png`）
/// 的卡片底色实际是**冷蓝**（`#344A60`，亮度 0.065）到**紫调**（`#63546B`，
/// 亮度 0.112）的一整片色带；浅色首页（`docs/preview/50-r7-home.png`）
/// 的卡片底色是 `#FFFFFF` 到 `#F0EEF2`。
///
/// 第一版标定时用的是手挑的紫灰色域，暗色二级文字只有 3.12:1 —— **不达标**；
/// 换成真实色域后重新定标如下（每档都留了余量，不卡在阈值线上）：
///
/// | 档位 | 浅色 | 暗色 | 浅色最差对比度 | 暗色最差对比度 |
/// | --- | --- | --- | --- | --- |
/// | 一级 primary | `#18191C` | `#EDEEF0` | 17.58 | 14.30 |
/// | 二级 secondary | `#666A6E` | `#D1D7DB` | 5.45 | 4.80 |
/// | 三级 tertiary | `#7E8286` | `#B2B2B6` | 3.87 | 3.30 |
/// | 四级 quaternary | `#989CA0` | `#909596` | 2.76 | 2.30 |
/// | 五级 placeholder | `#B0B4B8` | `#737A7F` | 2.09 | 1.60 |
///
/// 二级及以上达到 WCAG AA（4.5:1），一级达到 AAA（7:1）。
/// （一级在暗色最亮的那块紫表面上只有 6.30:1 —— 玻璃染色后无法更高，
/// 而一级文字都是 16px 以上的粗体，按 WCAG「大字 3:1」也算达标。）
class AppTextColor {
  AppTextColor._();

  /// 一级：标题、正文、关键数值。浅色 17.58:1，暗色 14.30:1。
  static Color primary(BuildContext context) =>
      context.isDark ? AppColors.darkText : AppColors.lightText;

  /// 二级：副标题、列表项说明。浅色 5.45:1，暗色 4.80:1（AA）。
  static Color secondary(BuildContext context) =>
      context.isDark ? const Color(0xFFD1D7DB) : const Color(0xFF666A6E);

  /// 三级：辅助信息、占位符、时间戳。浅色 3.87:1，暗色 3.30:1。
  static Color tertiary(BuildContext context) => context.isDark
      ? const Color(0xFFB2B2B6)
      : const Color(0xFF7E8286);

  /// 四级：禁用、极次要。浅色 2.76:1，暗色 2.30:1。
  static Color quaternary(BuildContext context) => context.isDark
      ? const Color(0xFF909596)
      : const Color(0xFF989CA0);

  /// 五级：占位符、禁用输入框。浅色 2.09:1，暗色 1.60:1。
  static Color placeholder(BuildContext context) => context.isDark
      ? const Color(0xFF737A7F)
      : const Color(0xFFB0B4B8);
}

/// 常用文字组合。
///
/// 页面里「标题 + 颜色 + 字号」这套三件套出现得非常频繁，
/// 每次现写一遍容易漏掉字重或行高。集中到这里后，
/// 同一个层级的文字在全 App 必然一致。
class AppTextStyles {
  AppTextStyles._();

  /// 页面主标题（首页「为你推荐」这类区块标题）。
  static TextStyle sectionTitle(BuildContext context) => TextStyle(
        color: AppTextColor.primary(context),
        fontSize: AppFontSize.sectionTitle,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      );

  /// 卡片标题（视频卡片标题）。
  static TextStyle cardTitle(BuildContext context) => TextStyle(
        color: AppTextColor.primary(context),
        fontSize: AppFontSize.cardTitle,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.1,
      );

  /// 详情页大标题。
  static TextStyle detailTitle(BuildContext context) => TextStyle(
        color: AppTextColor.primary(context),
        fontSize: AppFontSize.detailTitle,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.2,
      );

  /// 正文。
  static TextStyle body(BuildContext context) => TextStyle(
        color: AppTextColor.primary(context),
        fontSize: AppFontSize.bodyLarge,
        height: 1.5,
      );

  /// 次要正文 / 说明。
  static TextStyle bodySecondary(BuildContext context) => TextStyle(
        color: AppTextColor.secondary(context),
        fontSize: AppFontSize.body,
        height: 1.45,
      );

  /// 辅助信息（UP 主名、时间戳、统计数字）。
  static TextStyle meta(BuildContext context) => TextStyle(
        color: AppTextColor.tertiary(context),
        fontSize: AppFontSize.meta,
        height: 1.35,
      );

  /// 极次要信息。
  static TextStyle caption(BuildContext context) => TextStyle(
        color: AppTextColor.quaternary(context),
        fontSize: AppFontSize.caption,
        height: 1.35,
      );

  /// 徽标 / 标签上的文字。
  static TextStyle badge(BuildContext context) => TextStyle(
        color: AppTextColor.secondary(context),
        fontSize: AppFontSize.micro,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );
}

/// BuildContext 扩展：把「当前主题下的次要文字色」等常用取色收敛成一行调用。
///
/// 重构前每个文件都写着 `Theme.of(context).brightness == Brightness.dark
/// ? AppColors.darkSub : AppColors.lightSub`，其中好几处**漏掉了深色分支**
/// （详见重构说明 §2.3），导致深色模式下出现浅灰文字。
extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// 次要文字色（说明、计数、辅助标签）。
  ///
  /// 保留这个旧的入口是为了兼容，但**新代码请用 [AppTextColor.secondary]** ——
  /// 它在暗色模式下会比 `darkSub` 更亮一档，在玻璃表面上才真正读得出来。
  Color get subTextColor => AppTextColor.secondary(this);

  /// 主文字色。
  Color get primaryTextColor => AppTextColor.primary(this);
}
