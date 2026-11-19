import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/theme.dart';
import 'squircle.dart';

/// iOS 27 的选中态「液态玻璃透镜」。
///
/// 这一版按参考图重做，把三件事做对：
///
/// ## 1. 静止态是**柔边光晕**，不是实色块
///
/// 参考图（静止态）的选中项后面是一团**边缘完全化开**的彩色光晕，
/// 轮廓可辨但没有硬边 —— 像一团光透过玻璃，
/// 而不是一块贴在栏上的色片。所以底盘用「圆角矩形 + 高斯模糊」实现：
/// 形状靠模糊前的路径定义，边缘靠模糊化开。见 [SelectedGlow]。
///
/// ## 2. 抬起态是**大号透镜**，并且会顶出胶囊
///
/// iOS 的透镜在按下时不是「原地变透明」，而是**长大**：
/// 直径涨到图标槽的两倍多，向上**顶出底栏**，
/// 于是它不再是被胶囊裁剪的一段，而是浮在整条底栏之上的一颗玻璃珠。
///
/// 这也是为什么透镜必须画在胶囊的 `ClipPath` **之外** ——
/// 画在里面就永远顶不出去。
///
/// ## 3. 透镜内部有**色散**（chromatic aberration）
///
/// 参考图（抬起态）里被罩住的图标边缘有明显的青 / 品红镶边，
/// 透镜顶部还横着一道彩虹弧。
///
/// 物理上这是棱镜把白光拆成光谱：不同波长折射角不同，
/// 于是边缘的像素被**横向错开**成彩边。
///
/// 实现上分两层：
///
/// * **图标层**：把图标画三遍，各偏移 0.8pt，分别只保留 R / G / B 通道
///   并染成青 / 品红 —— 叠起来就是边缘的彩色错位；
/// * **玻璃层**：沿轮廓描一圈 `sweep` 彩虹，用加色混合画在玻璃上，
///   再在顶部压一道横贯的彩虹亮带。
class LiquidGlassDrop extends StatelessWidget {
  const LiquidGlassDrop({
    Key? key,
    required this.width,
    required this.height,
    required this.stretch,
    required this.lift,
    required this.child,
    this.tint,
    this.chromatic = 0.0,
    this.magnification = 1.14,
    this.shape,
  }) : super(key: key);

  /// 透镜的静止宽度。
  final double width;

  /// 透镜的静止高度。
  final double height;

  /// 拉伸系数：> 1 纵向拉长，< 1 横向压扁。
  final double stretch;

  /// 抬起程度：0 = 贴在底盘上，1 = 完全抬起。
  final double lift;

  /// 玻璃下面的内容（图标）。
  final Widget child;

  /// 玻璃的着色；null 表示用品牌粉。
  final Color? tint;

  /// 色散强度（0 ~ 1）。
  ///
  /// 静止态应为 0 —— 参考图里只有**抬起态**才有彩虹。
  final double chromatic;

  /// 折射放大倍率。
  ///
  /// 透镜越大，里面的内容就该被放得越大 ——
  /// 否则大透镜里会浮着一枚小图标，看着不像「放大镜」，
  /// 而像「图标旁边多了一块玻璃」。
  final double magnification;

  /// 透镜的轮廓；null 表示默认的**胶囊**。
  ///
  /// 抬起态用的是**圆**（参考图里那是一颗大玻璃珠），
  /// 静止态用的是胶囊（底栏本来就是胶囊形）。
  final Path Function(Rect rect)? shape;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;
    final Color accent = tint ?? AppColors.pink;

    // 拉伸时纵向变长、横向变窄；压扁时反之。
    final double w = width / math.sqrt(stretch);
    final double h = height * stretch;

    // 抬起越高，玻璃越通透 —— iOS 里「悬空的玻璃珠」
    // 比「平铺的色块」更透明，因为底盘已经让位给它。
    final double lifted = lift.clamp(0.0, 1.0);

    return SizedBox(
      width: w,
      height: h,
      child: Opacity(
        opacity: lifted.clamp(0.0, 1.0),
        child: _PrismBody(
          width: w,
          height: h,
          accent: accent,
          dark: dark,
          chromatic: chromatic,
          magnification: magnification,
          shape: shape,
          child: child,
        ),
      ),
    );
  }
}

/// 选中项的**柔边光晕**底盘。
///
/// 形状是圆角矩形（不是正圆），边缘用高斯模糊化开 ——
/// 参考图里那团光的轮廓是「可辨但没有硬边」的。
///
/// 尺寸刻意比图标槽大：光晕横向溢出约 90%、纵向溢出约 28%，
/// 这样一组「图标 + 文字」被光晕整块托住，而不是只有图标被托住。
class SelectedGlow extends StatelessWidget {
  const SelectedGlow({
    Key? key,
    this.tint,
  }) : super(key: key);

  /// 光晕的着色；null 表示用品牌粉。
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final Color accent = tint ?? AppColors.pink;

    return IgnorePointer(
      child: CustomPaint(
        painter: _SoftGlowPainter(
          accent: accent,
          dark: p.dark,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SoftGlowPainter extends CustomPainter {
  const _SoftGlowPainter({required this.accent, required this.dark});

  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // 传入的 size 就是光晕的**轮廓**尺寸（不二次放大）——
    // 尺寸预算统一由外部的度量类给出，这里只负责把边缘化开。
    final Rect rect = Offset.zero & size;

    // 连续曲率的圆角矩形：光晕的轮廓也要是 iOS 的曲线。
    final Path path = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(rect.height * 0.40),
    ).getOuterPath(rect);

    // 模糊半径随尺寸缩放：光晕越小，化开的边缘也越窄。
    final double sigma = rect.height * 0.16;

    // 两层：
    // 内层是较实的光核，外层是大范围的柔化余晖。
    final Paint core = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        <Color>[
          accent.withOpacity(dark ? 0.34 : 0.30),
          accent.withOpacity(dark ? 0.16 : 0.14),
          const Color(0xFF9A7BFF).withOpacity(dark ? 0.20 : 0.16),
        ],
        const <double>[0.0, 0.55, 1.0],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawPath(path, core);

    final Paint halo = Paint()
      ..color = accent.withOpacity(dark ? 0.16 : 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 2.0);
    canvas.drawPath(path, halo);
  }

  @override
  bool shouldRepaint(covariant _SoftGlowPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.dark != dark;
}

/// 悬起的透镜本体：透明玻璃珠 + 色散 + 暗边 + 棱镜彩虹弧。
class _PrismBody extends StatelessWidget {
  const _PrismBody({
    required this.width,
    required this.height,
    required this.accent,
    required this.dark,
    required this.chromatic,
    required this.magnification,
    required this.child,
    this.shape,
  });

  final double width;
  final double height;
  final Color accent;
  final bool dark;
  final double chromatic;
  final double magnification;
  final Widget child;

  /// 透镜轮廓；null 表示胶囊。
  final Path Function(Rect rect)? shape;

  @override
  Widget build(BuildContext context) {
    final Path shape = (this.shape ?? GlassShape.capsule)(
      Offset.zero & Size(width, height),
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 内部：近乎全透的淡色玻璃，只带一点点品牌色的暗示。
        //
        // 抬起态的透镜是很**通透**的 —— 参考图里几乎看不见玻璃本体，
        // 只看得到轮廓上那一圈彩虹边。所以这里的白色基底要压得很低，
        // 否则会把罩住的图标冲淡。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withOpacity(dark ? 0.14 : 0.34),
                accent.withOpacity(dark ? 0.08 : 0.12),
                Colors.white.withOpacity(dark ? 0.06 : 0.22),
              ],
            ),
          ),
        ),

        // 玻璃下的内容（图标）—— 会被「放大镜」折射放大。
        //
        // 这里用 `Transform.scale` 模拟放大镜：内容本身按 [magnification]
        // 倍渲染，再被透镜的形状裁切，于是边缘的内容会被「压」到边界上 ——
        // 这正是放大镜该有的样子。
        ClipPath(
          clipper: PathClipper(shape),
          child: Transform.scale(
            scale: magnification,
            child: _ChromaticSplit(
              amount: chromatic,
              child: child,
            ),
          ),
        ),

        // ---- 棱镜彩虹弧 ----
        //
        // 沿轮廓描一圈光谱：用 `sweep` 渐变让颜色沿周长变化，
        // 再用**加色混合**画在玻璃上（加色 = 发光）。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PrismArcPainter(
                shape: shape,
                intensity: chromatic,
              ),
            ),
          ),
        ),

        // Liquid Glass v2：暗边。
        //
        // iOS 27 给玻璃加了一圈**变暗的边缘**，让形状从背景里立起来。
        Positioned.fill(
          child: GlassShapeEdge(
            shape: this.shape ?? GlassShape.capsule,
            edgeColor: Colors.black.withOpacity(dark ? 0.30 : 0.14),
            edgeWidth: 1.4,
            innerShade: dark ? 0.24 : 0.08,
          ),
        ),

        // Liquid Glass v2：更亮的镜面高光 —— 上沿一道亮线。
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

/// 图标的**色散**（chromatic aberration）。
///
/// 把同一份图标画三遍，每遍只保留一个颜色通道并横向错开：
///
/// * 青色偏左上；
/// * 品红偏右下；
/// * 原色留在原位。
///
/// 三层叠起来，图标**边缘**就会出现青 / 品红的彩边 ——
/// 正是棱镜把光拆成光谱后、边缘像素横向错开的样子。
///
/// 色散强度为 0 时完全退化成原图标（只有一层），不产生额外开销。
class _ChromaticSplit extends StatelessWidget {
  const _ChromaticSplit({required this.child, required this.amount});

  final Widget child;

  /// 色散强度（0 ~ 1）。
  final double amount;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0.01) return child;

    // 0.5pt 的错位：足以看出彩边，又不至于把图标糊掉。
    final double d = amount * 0.5;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        // 青色偏左上。
        Transform.translate(
          offset: Offset(-d, -d * 0.45),
          child: Opacity(
            opacity: 0.38 * amount,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFF3BE8FF),
                BlendMode.srcATop,
              ),
              child: child,
            ),
          ),
        ),
        // 品红偏右下。
        Transform.translate(
          offset: Offset(d, d * 0.45),
          child: Opacity(
            opacity: 0.30 * amount,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFFF3EA5),
                BlendMode.srcATop,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// 沿玻璃轮廓的**棱镜彩虹弧**。
///
/// 用 `sweep` 渐变沿周长铺一圈光谱，用**加色混合**画上去 ——
/// 加色意味着「发光」，而不是「上色」。
///
/// 顶部（12 点方向）额外压一道横贯的彩虹亮带：
/// 参考图里透镜上沿那道彩虹最扎眼，是棱镜把光拆开后
/// 在上边缘汇聚出来的。
class _PrismArcPainter extends CustomPainter {
  const _PrismArcPainter({required this.shape, required this.intensity});

  final Path shape;

  /// 色散强度（0 ~ 1）。
  final double intensity;
  /// 光谱色序（按周长排列）。
  static const List<Color> _spectrum = <Color>[
    Color(0xFFFF3EA5),
    Color(0xFFFF6B3D),
    Color(0xFFFFD23D),
    Color(0xFF5BE37A),
    Color(0xFF3BE8FF),
    Color(0xFF4A6BFF),
    Color(0xFFB44BFF),
    Color(0xFFFF3EA5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;

    final Rect rect = Offset.zero & size;
    final Path path = shape;
    final Offset center = rect.center;

    // 沿轮廓描一圈光谱。
    //
    // `sweep` 从 12 点方向（-π/2）开始，于是彩虹的起点落在顶部 ——
    // 参考图里顶部那道彩虹亮带正是在这里。
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.sweep(
        center,
        _spectrum,
        const <double>[0.0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 1.0],
        TileMode.clamp,
        -math.pi / 2,
        -math.pi / 2 + math.pi * 2,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9);
    canvas.drawPath(path, arc);

    // 外扩一圈更淡更粗的光晕：彩虹不是一根线，而是一层薄光。
    final Paint halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.sweep(
        center,
        _spectrum,
        const <double>[0.0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 1.0],
        TileMode.clamp,
        -math.pi / 2,
        -math.pi / 2 + math.pi * 2,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);
    canvas.drawPath(path, halo);

    // 顶部横贯的彩虹亮带。
    //
    // 棱镜把光拆开后，光谱在上边缘汇聚成一条亮带 ——
    // 这是参考图里透镜上沿最鲜明的那道彩虹。
    //
    // 亮带只占顶部**很薄**的一层：再厚就会把透镜里的图标糊掉，
    // 而参考图里图标始终是清楚的，只是边缘镶了一圈彩边。
    final double bandH = size.height * 0.16;
    final Rect band = Rect.fromLTWH(
      rect.left + size.width * 0.12,
      rect.top + size.height * 0.03,
      size.width * 0.76,
      bandH,
    );
    final Paint bandPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        band.topLeft,
        band.bottomRight,
        <Color>[
          _spectrum[0].withOpacity(0.42 * intensity),
          _spectrum[3].withOpacity(0.30 * intensity),
          _spectrum[4].withOpacity(0.38 * intensity),
          _spectrum[6].withOpacity(0.28 * intensity),
        ],
        const <double>[0.0, 0.34, 0.66, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(band, bandPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PrismArcPainter oldDelegate) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.shape != shape;
}
