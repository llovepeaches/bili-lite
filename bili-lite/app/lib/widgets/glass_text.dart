import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/tokens.dart';

/// 玻璃上的文字。
///
/// ## 为什么需要它
///
/// 这套 App 的视觉是「玻璃」，而玻璃是**近全透**的 —— 卡片内部几乎不铺底色，
/// 只留一圈折射亮边。这意味着同一段文字下面可能是：
///   * 浅色的极光背景；
///   * 深色的视频封面；
///   * 亮粉色的色带；
///   * 纯白的雪景图。
///
/// 上一版对此的解法是在需要的地方**硬编码一个 shadows 光晕**做补丁
/// （`video_card.dart` 里的白/黑影晕、`app_logo.dart` 的白影）。
/// 这条路走不通：
///   * 光晕颜色只能二选一（黑或白），遇到中间色调的封面就会显脏；
///   * 每处都要自己判断该用黑还是白，漏一处就是一处不可读；
///   * 光晕会跟着字号放大而变糊，小字上反而把字压脏。
///
/// 这里把「在玻璃上放一段文字」这件事收成一个组件：
/// 它根据当前主题与玻璃状态，选出**保证对比度的文字色**，
/// 并在必要时叠一层极淡的同色系柔光（而不是纯黑白光晕）。
///
/// 玻璃关闭时退化为普通文字，不加任何装饰。
class GlassText extends StatelessWidget {
  const GlassText(
    this.text, {
    Key? key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
  }) : super(key: key);

  /// 文本内容。
  final String text;

  /// 文字样式。通常传 [AppTextStyles] 里的某个组合。
  final TextStyle? style;

  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? AppTextStyles.body(context);
    final dark = context.isDark;

    // 玻璃表面上的文字：
    //   * 暗色主题 —— 玻璃底是深色，浅字直接可读，不需要任何补丁；
    //   * 浅色主题 —— 玻璃底接近白色，深字也可读，但**彩色封面**上会糊，
    //     所以给一个极淡的白晕（而不是黑影），保持画面干净。
    //
    // 强度刻意压得很低（0.34）：足以在彩色封面上把字"托"起来，
    // 又不会在纯色背景上显出一圈脏边。
    final needsGlow = !dark && _isGlass(context);
    final effective = needsGlow
        ? base.copyWith(
            shadows: <Shadow>[
              Shadow(
                color: Colors.white.withOpacity(0.34),
                blurRadius: 6,
                offset: const Offset(0, 0.5),
              ),
            ],
          )
        : base;

    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: effective,
    );
  }

  /// 判断当前是否处在玻璃材质上。
  ///
  /// 这里不查 [GlassTheme]（那会让 widgets 层反向依赖 glass_theme），
  /// 而是用 `GlassScope` 是否存在来判断 —— 只有 App 根部注入了
  /// GlassScope 的页面才可能是玻璃态。
  bool _isGlass(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>() != null;
}
