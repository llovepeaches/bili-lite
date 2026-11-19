import 'package:flutter/material.dart';

import 'squircle.dart';

/// AndroidLiquidGlass `LiquidBottomTabs` 的 dock 视觉常量。
///
/// 数值逐一取自参考源码 `LiquidBottomTabs.kt` 与
/// `catalog/utils/DampedDragAnimation.kt`，不自行发明：
/// 64dp 容器 / 4dp 内边距 / 8dp 模糊 / 24dp 透镜 / 78÷56 按压比例。
class ReferenceDockStyle {
  const ReferenceDockStyle._();

  static const double barHeight = 64;
  static const double inset = 4;
  static const double blur = 8;
  static const double lensRefraction = 24;

  /// DampedDragAnimation：initialScale = 1f, pressedScale = 78f / 56f。
  static const double initialScale = 1;
  static const double pressedScale = 78 / 56;

  /// LiquidBottomTabs.onDrawSurface：
  /// 静止 `Color.Black.copy(0.1f)` / `Color.White.copy(0.1f)`；
  /// 按下 `drawRect(Color.Black.copy(alpha = 0.03f * progress))`。
  static const double idleSurfaceAlpha = 0.10;
  static const double pressedSurfaceAlpha = 0.03;

  /// 教程交互底栏与 tinted button：
  /// `val tint = Color(0xFF0088FF)` / `drawRect(tint, BlendMode.Hue)` /
  /// `drawRect(tint.copy(alpha = 0.75f))`。
  static const double tintAlpha = 0.75;

  /// 选中胶囊的折射蓝近似强度。源码的蓝来自透镜折射透明 tint 层，
  /// 是通透的；这里没有 GPU 色散透镜，用低透明度叠加近似，刻意远低于
  /// 独立 tint 按钮的 0.75，避免变成实心蓝。
  static const double selectionTintAlpha = 0.16;

  /// 教程交互底栏：`val maxScale = (size.width + 16f.dp.toPx()) / size.width`、
  /// `val scale = lerp(1f, maxScale, progress)`。
  static const double pressGrowPx = 16;

  /// DampedDragAnimation.layerBlock 的速度形变系数：
  /// `scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)`
  /// `scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)`
  /// 其中 `velocity = dampedDragAnimation.velocity / 10f`。
  static const double velocityX = 0.75;
  static const double velocityY = 0.25;
  static const double velocityClamp = 0.2;
}

/// 参考实现的强调色（源码 70~71 行）：
/// 浅色 `Color(0xFF0088FF)`，深色 `Color(0xFF0091FF)`。
Color referenceDockAccent(bool dark) =>
    dark ? const Color(0xFF0091FF) : const Color(0xFF0088FF);

/// 参考实现的容器表面色（源码 72~74 行）：
/// 浅色 `Color(0xFFFAFAFA).copy(0.4f)`，深色 `Color(0xFF121212).copy(0.4f)`。
Gradient referenceDockContainerGradient(bool dark) {
  final Color color = dark
      ? const Color(0x66121212) // alpha 0.4
      : const Color(0x66FAFAFA); // alpha 0.4
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[color, color],
  );
}

/// 参考 `LiquidBottomTabs` 的选中胶囊（源码 231~286 行的第三个 Box）。
///
/// 表面严格按源码 `onDrawSurface`：
/// * 静止 `Color.Black.copy(0.1f)`（浅）/ `Color.White.copy(0.1f)`（深），
///   `alpha = 1 - progress`；
/// * 按下再叠 `Color.Black.copy(alpha = 0.03f * progress)`。
///
/// 蓝色来自参考第三层下方的透明 tint 层，被 `lens(...)` 折射后显现；
/// 不是画在胶囊上的渐变，也不是独立 tinted button 的实心蓝——
/// 后者才用 `drawRect(tint, blendMode = BlendMode.Hue)` +
/// `drawRect(tint.copy(alpha = 0.75f))`，不能套到选中胶囊上。
///
/// 形变严格按 `DampedDragAnimation` 的 scaleX/scaleY + velocity 公式：
/// `pressedScale = 78/56`，`velocity/10` 后 `×0.75` / `×0.25`、clamp `±0.2`。
///
/// 关于色散：源码用 `lens(10p, 14p, chromaticAberration = true)`，
/// 这是 Backdrop 的 GPU 效果。Flutter 现有 `GlassSample` 只有 blur + lens 倍率，
/// 没有 `chromaticAberration` 参数；因此这里不手写文档中不存在的青 / 品红色值，
/// 只用低透明度 accent 近似折射蓝，并保留文档可复刻的高光 / 阴影 / 内阴影。
class ReferenceSelectionPill extends StatelessWidget {
  const ReferenceSelectionPill({
    Key? key,
    required this.progress,
    this.velocity = 0.0,
    required this.accent,
    required this.dark,
  }) : super(key: key);

  /// pressProgress：按下 / 拖动 / 飞行 → 1，松手 → 0。
  final double progress;

  /// 归一化横向速度（已按参考的 `velocity/10` 归一），静止为 0。
  final double velocity;

  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final double p = progress.clamp(0.0, 1.0);

    // 源码 layerBlock：
    //   scaleX = dampedDragAnimation.scaleX    (= lerp(1, pressedScale, p))
    //   scaleY = dampedDragAnimation.scaleY
    final double base = ReferenceDockStyle.initialScale +
        (ReferenceDockStyle.pressedScale - ReferenceDockStyle.initialScale) * p;

    // 源码：velocity = dampedDragAnimation.velocity / 10f；
    //   scaleX /= 1f - (velocity * 0.75f).fastCoerceIn(-0.2f, 0.2f)
    //   scaleY *= 1f - (velocity * 0.25f).fastCoerceIn(-0.2f, 0.2f)
    final double v = velocity.clamp(
      -ReferenceDockStyle.velocityClamp,
      ReferenceDockStyle.velocityClamp,
    );
    final double scaleX = base /
        (1 -
            (v * ReferenceDockStyle.velocityX).clamp(
                -ReferenceDockStyle.velocityClamp,
                ReferenceDockStyle.velocityClamp));
    final double scaleY = base *
        (1 -
            (v * ReferenceDockStyle.velocityY).clamp(
                -ReferenceDockStyle.velocityClamp,
                ReferenceDockStyle.velocityClamp));

    Path shape(Rect r) => GlassShape.capsule(r);

    // 源码 onDrawSurface 的两层中性表面。
    final Color idle = dark ? Colors.white : Colors.black;
    final Color pressed = Colors.black;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 源码 shadow = { Shadow(alpha = progress) }。
          GlassShapeShadow(
            shape: shape,
            shadows: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.24 * p),
                blurRadius: 12 * p,
                offset: Offset(0, 4 * p),
              ),
            ],
          ),
          // 源码 onDrawSurface：静止中性表面 (alpha = 1 - progress)。
          GlassShapeSurface(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                idle.withOpacity(ReferenceDockStyle.idleSurfaceAlpha * (1 - p)),
                idle.withOpacity(ReferenceDockStyle.idleSurfaceAlpha * (1 - p)),
              ],
            ),
          ),
          // 源码 onDrawSurface：按下叠 Black@0.03*progress。
          if (p > 0.001)
            Positioned.fill(
              child: IgnorePointer(
                child: GlassShapeSurface(
                  shape: shape,
                  gradient: LinearGradient(
                    colors: <Color>[
                      pressed.withOpacity(
                          ReferenceDockStyle.pressedSurfaceAlpha * p),
                      pressed.withOpacity(
                          ReferenceDockStyle.pressedSurfaceAlpha * p),
                    ],
                  ),
                ),
              ),
            ),
          // 源码选中胶囊表面本身是**中性色**（上面两层），蓝色来自
          // `lens(10p, 14p, chromaticAberration)` 折射第 225 行那层
          // `alpha(0f) + colorFilter.tint(accent)` 的透明 tint 层 ——
          // 所以参考里的蓝是「通透的折射蓝」，不是实心蓝。
          //
          // Flutter 没有 GPU 色散透镜，无法复刻折射；这里用一层低透明度的
          // accent 叠加近似「透出来的一点蓝」，随 pressProgress 淡入。
          // 注意：教程里 tint@Hue + @0.75 是给**独立图标按钮**的（整枚该是蓝的），
          // 不能套在选中胶囊上，否则会变成实心蓝、反而偏离参考。
          if (p > 0.001)
            Opacity(
              opacity: p,
              child: _ReferenceTintLayer(
                shape: shape,
                color: accent,
                alpha: ReferenceDockStyle.selectionTintAlpha,
              ),
            ),
          // 源码 highlight = { Highlight.Default.copy(alpha = progress) }、
          // innerShadow = { InnerShadow(radius = 8dp * progress, alpha = progress) }。
          GlassShapeEdge(
            shape: shape,
            edgeColor: Colors.white.withOpacity(0.14 + 0.30 * p),
            edgeWidth: 1.2,
            innerShade: 0.04 + 0.14 * p,
          ),
        ],
      ),
    );
  }
}

/// 参考选中胶囊下方透明 tint 层在 Flutter 侧的近似：
/// 用文档规定的 accent 色做低透明度叠加，按给定胶囊形状裁剪。
/// 源码靠 `alpha(0f) + colorFilter.tint(accent)` 让上层透镜折射出蓝；
/// Flutter 没有对应 GPU 路径，这里只近似最终观感，
/// 不使用独立 tinted button 的实心蓝参数。
class _ReferenceTintLayer extends StatelessWidget {
  const _ReferenceTintLayer({
    required this.shape,
    required this.color,
    required this.alpha,
  });

  final Path Function(Rect) shape;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _TintPainter(color: color, alpha: alpha, shape: shape),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TintPainter extends CustomPainter {
  const _TintPainter({
    required this.color,
    required this.alpha,
    required this.shape,
  });

  final Color color;
  final double alpha;
  final Path Function(Rect) shape;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.save();
    canvas.clipPath(shape(rect));
    // 源码 tint 层是 alpha(0f) + colorFilter.tint(accent)，靠透镜折射才显蓝。
    // Flutter 无对应 GPU 折射，改用低透明度 accent 叠加近似「透出的蓝」。
    // 不在白底上用 BlendMode.hue —— 那会把中性表面直接染成实心蓝。
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withOpacity(alpha)
        ..blendMode = BlendMode.srcOver,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TintPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.alpha != alpha;
}
