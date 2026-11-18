import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// iOS 风格的**连续曲率**形状（continuous curvature / squircle）。
///
/// ## 为什么不用 `BorderRadius.circular`
///
/// `BorderRadius.circular` 画出来的是一段**正圆弧**。正圆弧在切点处
/// 曲率会从 0（直线段）突然跳到 1/r（圆弧）—— 那个「曲率突变点」
/// 就是肉眼看到的「圆角是硬贴上去的」那种生硬感。
///
/// iOS 从 7 时代起就在所有圆角控件上用**连续曲率**：曲率从直线的 0
/// 平滑地长到峰值、再平滑地落回 0，整条轮廓的曲率处处连续。
/// 数学上它接近一条**超椭圆**（superellipse，`|x/a|^n + |y/b|^n = 1`，
/// n ≈ 5），也就是 iOS 图标的形状。
///
/// Flutter 自带的 [ContinuousRectangleBorder] 正是这个形状的实现：
/// 角部用三次贝塞尔在「直线段」与「圆角」之间做平滑过渡，
/// 而不是像 [RoundedRectangleBorder] 那样用正圆弧硬接。
///
/// ## 关键约束：路径必须三处一致
///
/// 底栏的玻璃要同时出现在三个地方：
///
/// 1. 共享 backdrop 的裁剪（决定「透过去看到什么」）；
/// 2. 表面层的渐变填充；
/// 3. 最上层的暗边描线。
///
/// 这三处如果用了不同的形状，backdrop 采样的边缘就会漏出缝。
/// 所以这里统一由 [GlassShape] 生成路径，三处共用同一个函数。
///
/// ## 顺带修掉的一个隐藏问题
///
/// Flutter 3.0 的 `ContinuousRectangleBorder._getPath` 在画角部时
/// 把 X/Y 半径用反了（`tlRadiusX` 参与水平位移、`tlRadiusY` 参与垂直位移），
/// 非正方形的圆角会画歪。底栏所有圆角都是正圆半径（水平 == 垂直），
/// 所以不受影响；但这也意味着**这里只用正圆半径**。
class GlassShape {
  GlassShape._();

  /// 底栏胶囊的连续曲率圆角半径。
  ///
  /// 胶囊高度的一半 —— 两端各是一个半圆角。
  static double capsuleRadius(double height) => height / 2;

  /// 生成一条**胶囊**路径（两端为连续曲率圆角，中间是直边）。
  static Path capsule(Rect rect) {
    return ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(capsuleRadius(rect.height)),
    ).getOuterPath(rect);
  }

  /// 生成一条**圆**路径（独立圆形按钮）。
  static Path circle(Rect rect) {
    return Path()..addOval(rect);
  }

  /// 生成「胶囊 ∪ 圆形」的并集路径。
  ///
  /// 底栏的两件玻璃要共享同一份 backdrop 采样，所以先用一条并集路径
  /// 把模糊层裁好，再在里面各套一层自己的透镜。
  static Path union(Rect capsuleRect, Rect? circleRect) {
    final Path path = capsule(capsuleRect);
    if (circleRect != null) {
      path.addOval(circleRect);
    }
    return path;
  }
}

/// 按一条自定义路径裁剪子控件。
///
/// 底栏的玻璃层要按「胶囊 ∪ 圆形」的形状裁剪，
/// 而胶囊的两端必须是**连续曲率**而不是正圆弧 ——
/// 这就是 iOS 的 tab bar 看起来更贵的一个细节。
class PathClipper extends CustomClipper<Path> {
  const PathClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant PathClipper oldClipper) => true;
}

/// 按一条自定义路径填充渐变（并可描边）的表面层。
///
/// 不用 `BoxDecoration` 是因为它只支持 `BorderRadius`（正圆弧）；
/// 不用 `ShapeDecoration` 是因为 Flutter 3.0 的 `BoxPainter` 没有
/// `shouldRepaint`，装饰器的重绘判定不可靠。这里直接 `CustomPaint`，
/// 形状、渐变、描边都在一处画完。
class GlassShapeSurface extends StatelessWidget {
  const GlassShapeSurface({
    Key? key,
    required this.shape,
    this.gradient,
    this.borderColor,
    this.borderWidth = 1.0,
    this.child,
  }) : super(key: key);

  /// 形状：给定矩形，返回要填充的路径。
  final Path Function(Rect rect) shape;

  /// 表面渐变。
  final Gradient? gradient;

  /// 描边颜色。
  final Color? borderColor;

  /// 描边宽度。
  final double borderWidth;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlassShapeSurfacePainter(
        shape: shape,
        gradient: gradient,
        borderColor: borderColor,
        borderWidth: borderWidth,
      ),
      child: child,
    );
  }
}

class _GlassShapeSurfacePainter extends CustomPainter {
  const _GlassShapeSurfacePainter({
    required this.shape,
    required this.gradient,
    required this.borderColor,
    required this.borderWidth,
  });

  final Path Function(Rect rect) shape;
  final Gradient? gradient;
  final Color? borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Path path = shape(rect);

    final Gradient? g = gradient;
    if (g != null) {
      canvas.drawPath(path, Paint()..shader = g.createShader(rect));
    }

    final Color? border = borderColor;
    if (border != null && border.alpha != 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = border,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassShapeSurfacePainter oldDelegate) =>
      oldDelegate.gradient != gradient ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth;
}

/// 沿一条自定义路径画一圈内阴影与暗边（Liquid Glass v2 的 darkened edge）。
///
/// iOS 27 给玻璃加了一圈**变暗的边缘**，配合更亮的镜面高光，
/// 玻璃才有立体感 —— 否则它只是一张半透明的色片。
///
/// 实现：在形状内侧压一圈很窄的黑（内阴影），再叠一条细边把形状「勒」出来。
class GlassShapeEdge extends StatelessWidget {
  const GlassShapeEdge({
    Key? key,
    required this.shape,
    required this.edgeColor,
    this.edgeWidth = 1.4,
    this.innerShade = 0.0,
  }) : super(key: key);

  final Path Function(Rect rect) shape;
  final Color edgeColor;
  final double edgeWidth;

  /// 内侧压暗的强度（0 ~ 1）。
  final double innerShade;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GlassShapeEdgePainter(
          shape: shape,
          edgeColor: edgeColor,
          edgeWidth: edgeWidth,
          innerShade: innerShade,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GlassShapeEdgePainter extends CustomPainter {
  const _GlassShapeEdgePainter({
    required this.shape,
    required this.edgeColor,
    required this.edgeWidth,
    required this.innerShade,
  });

  final Path Function(Rect rect) shape;
  final Color edgeColor;
  final double edgeWidth;
  final double innerShade;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Path path = shape(rect);

    if (innerShade > 0) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = edgeWidth * 3.2
          ..color = Colors.black.withOpacity(innerShade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth
        ..color = edgeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassShapeEdgePainter oldDelegate) =>
      oldDelegate.edgeColor != edgeColor ||
      oldDelegate.edgeWidth != edgeWidth ||
      oldDelegate.innerShade != innerShade;
}

/// 沿一条自定义路径画柔和投影。
///
/// `BoxShadow` 只能贴在 `BorderRadius` 上，画不出连续曲率形状的影子。
/// 这里用「同形路径 + 高斯模糊」来近似。
class GlassShapeShadow extends StatelessWidget {
  const GlassShapeShadow({
    Key? key,
    required this.shape,
    required this.shadows,
  }) : super(key: key);

  final Path Function(Rect rect) shape;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GlassShapeShadowPainter(shape: shape, shadows: shadows),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GlassShapeShadowPainter extends CustomPainter {
  const _GlassShapeShadowPainter({
    required this.shape,
    required this.shadows,
  });

  final Path Function(Rect rect) shape;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Path path = shape(rect);

    for (final BoxShadow shadow in shadows) {
      if (shadow.color.alpha == 0) continue;
      canvas.save();
      canvas.translate(shadow.offset.dx, shadow.offset.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = shadow.color
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GlassShapeShadowPainter oldDelegate) =>
      !listEquals(oldDelegate.shadows, shadows);
}
