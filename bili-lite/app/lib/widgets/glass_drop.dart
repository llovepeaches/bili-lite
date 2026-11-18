import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/theme.dart';

/// iOS 26/27 的选中态「玻璃水滴」。
///
/// 它和旧版的「粉色圆角方块」有本质区别：
///
/// * **它是一颗「水滴」，不是一块方块** —— 形状是圆角胶囊，
///   而且**跟着运动方向变形**（飞行时纵向拉长、落位时横向压扁）。
/// * **底盘会淡出** —— iOS 27 的原话是 *"its platter fades so it becomes
///   clear glass"*：抬起之后，水滴从「贴在栏上的有色块」变成
///   「一颗悬着的透明玻璃珠」。
/// * **它是玻璃，不是一块实色** —— 内部近乎全透，能看到底下的图标，
///   而底下的图标还因为折射被**放大**了。
/// * **它有暗边和更亮的镜面高光** —— Liquid Glass v2 新增的
///   *"darkened edge plus brighter specular highlights"*。
///
/// 颜色上沿用 B 站粉做玻璃的着色（而不是 iOS 的系统蓝），
/// 但**底栏本身**是 iOS 那种奶白 / 烟熏玻璃。
class LiquidGlassDrop extends StatelessWidget {
  const LiquidGlassDrop({
    Key? key,
    required this.width,
    required this.height,
    required this.stretch,
    required this.lift,
    required this.child,
    this.tint,
  }) : super(key: key);

  /// 水滴的静止宽度。
  final double width;

  /// 水滴的静止高度。
  final double height;

  /// 拉伸系数：> 1 纵向拉长，< 1 横向压扁。
  final double stretch;

  /// 抬起程度：0 = 贴在底盘上，1 = 完全悬起。
  final double lift;

  /// 玻璃下面的内容（图标 + 文字）。
  final Widget child;

  /// 玻璃的着色；null 表示用品牌粉。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;
    final Color accent = tint ?? AppColors.pink;

    // 拉伸时纵向变长、横向变窄；压扁时反之。
    final double w = width / math.sqrt(stretch);
    final double h = height * stretch;

    // 抬起越高，底盘越透明（变成通透玻璃），但**边缘反而更亮** ——
    // 这是 iOS 里「悬空的玻璃珠」比「平铺的色块」更通透的原因。
    final double lifted = lift.clamp(0.0, 1.0);
    final double platterFade = 1 - 0.72 * lifted;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ---- 底盘：贴到底栏上的那层有色玻璃 ----
          //
          // 抬起时它淡出，但**留一点**，于是水滴不会凭空出现 ——
          // 视觉上是「从底盘上长起来」而不是「凭空出现」。
          Opacity(
            opacity: platterFade.clamp(0.0, 1.0),
            child: _Platter(
              width: w,
              height: h,
              accent: accent,
              dark: dark,
            ),
          ),

          // ---- 水滴本体：悬起的透明玻璃珠 ----
          //
          // 抬起时它接管底盘的视觉，内部近乎全透，能看见底下的图标。
          Opacity(
            opacity: lifted.clamp(0.0, 1.0),
            child: _DropBody(
              width: w,
              height: h,
              accent: accent,
              dark: dark,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 贴到底栏上的底盘。
class _Platter extends StatelessWidget {
  const _Platter({
    required this.width,
    required this.height,
    required this.accent,
    required this.dark,
  });

  final double width;
  final double height;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withOpacity(dark ? 0.44 : 0.36),
            accent.withOpacity(dark ? 0.22 : 0.16),
            const Color(0xFF9A7BFF).withOpacity(dark ? 0.26 : 0.18),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(dark ? 0.58 : 0.92),
          width: 1.1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withOpacity(dark ? 0.38 : 0.28),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

/// 悬起的水滴本体：透明玻璃珠 + 暗边 + 镜面高光 + 放大镜折射。
class _DropBody extends StatelessWidget {
  const _DropBody({
    required this.width,
    required this.height,
    required this.accent,
    required this.dark,
    required this.child,
  });

  final double width;
  final double height;
  final Color accent;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 内部：近乎全透的淡色玻璃，只带一点点品牌色的暗示。
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withOpacity(dark ? 0.16 : 0.52),
                accent.withOpacity(dark ? 0.10 : 0.16),
                Colors.white.withOpacity(dark ? 0.08 : 0.34),
              ],
            ),
          ),
        ),

        // 玻璃下的内容（图标 + 文字）—— 会被「放大镜」折射放大。
        //
        // 这里用 `Transform.scale` 模拟放大镜：内容本身按 1.14 倍渲染，
        // 再被水滴的形状裁切，于是边缘的内容会被「压」到边界上 ——
        // 这正是放大镜该有的样子。
        ClipRRect(
          borderRadius: radius,
          child: Transform.scale(
            scale: 1.14,
            child: child,
          ),
        ),

        // Liquid Glass v2：暗边。
        //
        // iOS 27 给玻璃加了一圈**变暗的边缘**，让形状从背景里立起来。
        // 这里用一层内外阴影模拟 —— 内阴影压暗边缘，
        // 外阴影则让玻璃「浮」在底栏上。
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: Colors.black.withOpacity(dark ? 0.30 : 0.14),
              width: 1.4,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(dark ? 0.34 : 0.18),
                blurRadius: 6,
                spreadRadius: -2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),

        // Liquid Glass v2：更亮的镜面高光 —— 上沿一道亮线 + 斜向环境光。
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.white.withOpacity(dark ? 0.34 : 0.88),
                Colors.white.withOpacity(0),
              ],
              stops: const <double>[0.0, 0.42],
            ),
          ),
        ),

        // 上沿一道折射亮线。
        Positioned(
          left: width * 0.16,
          right: width * 0.16,
          top: 0.9,
          height: 1.2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.white.withOpacity(0),
                    Colors.white.withOpacity(dark ? 0.70 : 1.0),
                    Colors.white.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
