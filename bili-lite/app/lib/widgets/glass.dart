import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/theme.dart';
import '../core/tokens.dart';

/// 把历史调用里带 alpha 的 tint 收敛为实色。
///
/// 旧版玻璃靠 `withOpacity` 叠出通透层次；扁平化后这些色值被混回卡片底色，
/// 只保留色相语义，不再产生任何半透明叠层。
Color _solidTint(Color tint, Color base) {
  if (tint.alpha == 255) return tint;
  return Color.lerp(base, tint, tint.alpha / 255) ?? base;
}

/// 页面纯色底。
///
/// 扁平化改版后这里不再绘制极光、镜面色带或半透明叠层，
/// 只保留一个不透光的主题背景，给上层内容提供稳定的画布。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({Key? key, required this.config}) : super(key: key);

  /// 兼容旧调用；扁平样式下不再读取配置。
  final GlassConfig config;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
  }
}

/// 统一卡片容器。
///
/// 保留原有构造函数，方便各页面零改动接入；视觉上改为纯色卡片 +
/// 克制的 1px 边框，不再有背景模糊、折射亮边、色散、辉光或半透明填充。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    Key? key,
    required this.child,
    this.radius = AppRadius.panel,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.blur,
    this.elevated = false,
    this.showSheen = true,
    this.shadowless = false,
    this.onTap,
    this.onLongPress,
    this.fillScale = 1.0,
    this.specular = false,
  }) : super(key: key);

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double? blur;
  final bool elevated;
  final bool showSheen;
  final bool shadowless;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double fillScale;
  final bool specular;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final Color base = dark ? AppColors.darkCard : AppColors.lightCard;
    final Color background = tint == null ? base : _solidTint(tint!, base);

    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? AppColors.darkLine : AppColors.lightLine,
          width: 1,
        ),
      ),
      child: child,
    );

    if (onTap == null && onLongPress == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: body,
    );
  }
}

/// 应用栏纯色底。
class GlassBar extends StatelessWidget {
  const GlassBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
  }
}

/// 小标签 / 徽标：实色胶囊，覆盖在封面等深色内容时使用深墨色。
class GlassPill extends StatelessWidget {
  const GlassPill({
    Key? key,
    required this.child,
    this.tint,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.onDark = false,
    this.onTap,
  }) : super(key: key);

  final Widget child;
  final Color? tint;
  final bool onDark;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final Color base = dark ? AppColors.darkCard : AppColors.lightCard;
    final Color background;
    if (onDark) {
      background = const Color(0xFF18191C);
    } else if (tint != null) {
      background = _solidTint(tint!, base);
    } else {
      background = base;
    }

    final Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );

    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

/// 通用芯片 / 按钮：选中态用浅粉实底，未选中态白底黑边。
class GlassChip extends StatelessWidget {
  const GlassChip({
    Key? key,
    required this.label,
    this.icon,
    this.leading,
    this.selected = false,
    this.onTap,
    this.radius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.labelStyle,
    this.tint,
  }) : super(key: key);

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final TextStyle? labelStyle;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final Color background = selected
        ? AppColors.pinkSoft
        : (dark ? AppColors.darkCard : AppColors.lightCard);
    final Color borderColor = selected
        ? AppColors.pinkSoft
        : (dark ? AppColors.darkLine : const Color(0xFF1B1C1F));
    final Color contentColor = dark ? Colors.white : const Color(0xFF18191C);
    final TextStyle effectiveStyle = (labelStyle ??
            TextStyle(
              fontSize: AppFontSize.label,
              color: contentColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ))
        .copyWith(color: contentColor);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected && leading == null && icon == null) ...<Widget>[
              Icon(Icons.check_rounded, size: 15, color: contentColor),
              const SizedBox(width: 5),
            ],
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 6)
            ],
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: contentColor),
              const SizedBox(width: 6),
            ],
            Text(label, style: effectiveStyle),
          ],
        ),
      ),
    );
  }
}

/// 封面上的播放按钮：纯色深墨圆 + 白色图标。
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    Key? key,
    required this.icon,
    required this.onTap,
    this.size = 58,
  }) : super(key: key);

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF18191C),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.46),
      ),
    );
  }
}

/// 分组标题前的实色短条。
class GlassAccent extends StatelessWidget {
  const GlassAccent({Key? key, this.height = 15}) : super(key: key);

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 普通分隔线：实色 1px，不再使用渐隐半透明层。
class GlassDivider extends StatelessWidget {
  const GlassDivider({Key? key, this.vertical = false, this.thickness = 1})
      : super(key: key);

  final bool vertical;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? thickness : null,
      height: vertical ? null : thickness,
      color: Theme.of(context).dividerColor,
    );
  }
}

class GlassDecorations {
  GlassDecorations._();

  /// TabBar 选中态：浅粉圆角实底，文字保持黑色。
  static Decoration tabIndicator(BuildContext context) => BoxDecoration(
        color: AppColors.pinkSoft,
        borderRadius: BorderRadius.circular(12),
      );

  static Color tabLabelColor(BuildContext context) =>
      context.isDark ? AppColors.pink : const Color(0xFF18191C);

  static Color tabUnselectedLabelColor(BuildContext context) =>
      context.isDark ? AppColors.darkSub : const Color(0xFF18191C);

  static EdgeInsets get tabIndicatorPadding =>
      const EdgeInsets.symmetric(horizontal: -14, vertical: 9);
}
