import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/theme.dart';
import 'glass_sample.dart';

/// 动态极光背景：漂移的彩色光晕 + 斜向色带 + 掠光。
///
/// iOS 的 Liquid Glass 之所以能"折射出颜色"，靠的是玻璃下面真有内容。
/// 这里用色带与光斑给透镜提供可被弯折、可被染色的底层，玻璃叠在其上才有意义。
/// 关闭玻璃或关闭动效时退化为静态底色，几乎零开销。
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({Key? key, required this.config}) : super(key: key);

  final GlassConfig config;

  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<GlassBackdrop>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GlassBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final needMotion = widget.config.enabled && widget.config.motion;
    if (needMotion && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 28),
      )..repeat();
    } else if (!needMotion && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _aurora(double t, bool dark) {
    final alpha = GlassPalette(
      dark,
      0.62 + 0.38 * (widget.config.enabled ? widget.config.strength : 0),
      tinted: widget.config.tinted,
    ).auroraAlpha *
        (widget.config.tinted ? 0.84 : 1.0);
    return RepaintBoundary(
      child: CustomPaint(
        isComplex: true,
        painter: _AuroraPainter(phase: t, dark: dark, alpha: alpha),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = GlassPalette(
      dark,
      widget.config.enabled ? 0.62 + 0.38 * widget.config.strength : 0.0,
      tinted: widget.config.tinted,
    );
    final controller = _controller;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: p.backdrop))),
        if (widget.config.enabled)
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (_, __) =>
                  Positioned.fill(child: _aurora(controller.value, dark)),
            )
          else
            Positioned.fill(child: _aurora(0.28, dark)),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  /// 把 28 秒动画量化成 48 步：光晕每 ~0.6s 才真正重绘一次，
  /// Web 的 html renderer 下省掉绝大多数全屏渐变重绘。
  _AuroraPainter(
      {required double phase, required this.dark, required this.alpha})
      : t = (phase * 48).roundToDouble() / 48;

  final double t;
  final bool dark;
  final double alpha;

  void _band(Canvas canvas, Size size, double cx, double cy, double width,
      double angle, Color color, double a) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(
        center: Offset.zero, width: width, height: size.longestSide * 2.0);
    final g = ui.Gradient.linear(
      Offset(-width / 2, 0),
      Offset(width / 2, 0),
      <Color>[
        color.withOpacity(0),
        color.withOpacity(a),
        color.withOpacity(a * 0.42),
        color.withOpacity(0),
      ],
      const <double>[0.0, 0.38, 0.62, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = g);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = math.max(w, h);
    const double tau = math.pi * 2;
    final a = alpha;

    // 可被玻璃"折射"的宽色带：模拟壁纸里的大块颜色。
    _band(canvas, size, w * (0.20 + 0.05 * math.sin(t * tau)), h * 0.48,
        w * 0.26, -0.44, AppColors.pink, a * 0.34);
    _band(canvas, size, w * (0.74 + 0.05 * math.cos(t * tau * 0.8)), h * 0.55,
        w * 0.22, -0.44, AppColors.blue, a * 0.32);
    _band(canvas, size, w * (0.48 + 0.04 * math.sin(t * tau * 0.6 + 1)),
        h * 0.92, w * 0.30, -0.44, const Color(0xFF9A7BFF), a * 0.22);

    final blobs = <List<double>>[
      <double>[0.14 + 0.09 * math.sin(t * tau), 0.14 + 0.07 * math.cos(t * tau * 0.8), 0.62, 0],
      <double>[0.88 + 0.07 * math.cos(t * tau * 0.7), 0.24 + 0.10 * math.sin(t * tau), 0.56, 1],
      <double>[0.30 + 0.12 * math.sin(t * tau * 0.6 + 1), 0.88 + 0.07 * math.cos(t * tau * 0.9), 0.60, 2],
      <double>[0.78 + 0.09 * math.cos(t * tau * 0.5 + 2), 0.82 + 0.08 * math.sin(t * tau * 1.1), 0.50, 3],
    ];
    final colors = <Color>[
      AppColors.pink,
      AppColors.blue,
      const Color(0xFF8B6BFF),
      const Color(0xFF38D9C4),
    ];

    for (var i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      final center = Offset(b[0] * w, b[1] * h);
      final radius = b[2] * scale;
      final c = colors[i];
      final shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[c.withOpacity(a), c.withOpacity(a * 0.32), c.withOpacity(0)],
        const <double>[0.0, 0.55, 1.0],
      );
      canvas.drawCircle(center, radius, Paint()..shader = shader);
    }

    // 斜向掠光：模拟环境光扫过玻璃表面。
    final beam = ui.Gradient.linear(
      Offset(0, h),
      Offset(w, 0),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(dark ? 0.045 : 0.14),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.22, 0.52, 0.80],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = beam);
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.dark != dark || oldDelegate.alpha != alpha;
}

// ---------------------------------------------------------------------------
// 透镜光学层
//
// iOS 26 Liquid Glass 的视觉定义：内部透明，沿形状边缘产生外部高光，
// 光线在边缘被弯折、聚集（lensing），并随移动出现镜面亮斑与轻微色散。
// 这里没有任何 shader / backdrop 采样，全部用 Canvas 上的多层描边与渐变
// 路径模拟，因此 Web 的 html renderer 也能稳定渲染。
// ---------------------------------------------------------------------------
class _LensPainter extends CustomPainter {
  const _LensPainter({
    required this.dark,
    required this.radius,
    required this.edge,
    required this.shade,
    required this.specular,
    required this.dispersion,
    required this.sheen,
    required this.phase,
    required this.warm,
    required this.cool,
    this.strong = false,
  });

  final bool dark;
  final double radius;
  final double edge;
  final double shade;
  final double specular;
  final double dispersion;
  final double sheen;
  final double phase;
  final Color warm;
  final Color cool;
  final bool strong;

  RRect _shape(Rect rect, double inset) => RRect.fromRectAndRadius(
        rect.deflate(inset),
        Radius.circular(math.max(0, radius - inset)),
      );

  void _specularArc(Canvas canvas, RRect shape, double strength) {
    // 用一条窄渐变亮带扫过轮廓，模拟沿边缘流动的镜面高光。
    // 刻意不用 Path.computeMetrics()/extractPath()：Flutter Web 的 html renderer
    // 遇到这类路径会切出独立的 z-index:-1 渲染层，把同容器里的文字盖到背景下面。
    final rect = shape.outerRect;
    final double travel = rect.width + 240.0;
    final double x = rect.left - 120.0 + (phase % 1.0) * travel;
    final grad = ui.Gradient.linear(
      Offset(x - 105, rect.top - 24),
      Offset(x + 105, rect.bottom + 24),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(specular * strength * 0.16),
        Colors.white.withOpacity(specular * strength * 0.96),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.32, 0.55, 1.0],
    );
    // 外层柔光 + 内层亮芯，全部走 drawRRect，保持单一渲染层。
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strong ? 6.0 : 4.2
        ..shader = grad,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strong ? 2.2 : 1.6
        ..shader = grad,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1) 顶部厚度高光与斜向环境光：极薄，避免把玻璃重新糊成白板。
    final top = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height * 0.42),
      <Color>[Colors.white.withOpacity(sheen), Colors.white.withOpacity(0)],
    );
    canvas.drawRect(rect, Paint()..shader = top);

    final sweep = ui.Gradient.linear(
      Offset(-size.width * 0.05, -size.height * 0.05),
      Offset(size.width * 0.82, size.height * 0.70),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(sheen * 0.52),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.40, 0.76],
    );
    canvas.drawRect(rect, Paint()..shader = sweep);

    // 2) 内侧折射环：由外向内的亮度梯度，模拟边缘聚光与透镜暗沿。
    final rings = <List<double>>[
      <double>[1.2, 1.0, edge * 0.52],
      <double>[2.8, 2.0, edge * 0.22],
      <double>[5.4, 3.0, edge * 0.08],
    ];
    for (final r in rings) {
      canvas.drawRRect(
        _shape(rect, r[0]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r[1]
          ..color = Colors.white.withOpacity(r[2]),
      );
    }
    canvas.drawRRect(
      _shape(rect, 7.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = Colors.black.withOpacity(shade * 0.30),
    );

    // 3) 色散：沿边缘一侧偏青、一侧偏粉，模拟玻璃的色差。
    final disp = ui.Gradient.linear(
      Offset(0, size.height),
      Offset(size.width, 0),
      <Color>[
        cool.withOpacity(dispersion),
        Colors.white.withOpacity(0),
        warm.withOpacity(dispersion * 0.92),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.34, 0.64, 1.0],
    );
    canvas.drawRRect(
      _shape(rect, 1.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = disp,
    );

    // 4) 外部高光环：左上、右下最亮，中间近乎消失。
    final hi = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, size.height),
      <Color>[
        Colors.white.withOpacity(edge * 0.98),
        Colors.white.withOpacity(edge * 0.08),
        Colors.white.withOpacity(edge * 0.14),
        Colors.white.withOpacity(edge * 0.78),
      ],
      const <double>[0.0, 0.30, 0.66, 1.0],
    );
    canvas.drawRRect(
      _shape(rect, 0.35),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strong ? 1.8 : 1.35
        ..shader = hi,
    );

    // 5) 镜面亮斑：沿轮廓缓慢流动 / 静止，随交互增强。
    _specularArc(canvas, _shape(rect, 0.9), strong ? 1.0 : 0.72);
  }

  @override
  bool shouldRepaint(_LensPainter old) =>
      old.dark != dark ||
      old.radius != radius ||
      old.edge != edge ||
      old.shade != shade ||
      old.specular != specular ||
      old.dispersion != dispersion ||
      old.sheen != sheen ||
      old.phase != phase ||
      old.strong != strong;
}

double _phaseOf(double v) => (v * 24).roundToDouble() / 24;

double _staticPhase(double radius) => 0.06 + (radius % 11) * 0.021;

LinearGradient _thin(LinearGradient g, double k) {
  if (k >= 1.0) return g;
  return LinearGradient(
    begin: g.begin,
    end: g.end,
    stops: g.stops,
    colors: g.colors
        .map<Color>((Color c) => c.withOpacity((c.alpha / 255.0) * k))
        .toList(),
  );
}

/// 玻璃面板：近乎全透的内部 + 渐变边框 + 透镜光学层 + 柔和外阴影。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    Key? key,
    required this.child,
    this.radius = 22,
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

  /// 内容让位：卡片把内部填充再压薄，让封面/文字成为主体。
  final double fillScale;

  /// 只有导航壳等大面积玻璃订阅全局镜面时钟，避免几十个 painter 同时动画。
  final bool specular;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    const double border = 1.2;

    final Widget body = config.enabled
        ? _glassBody(context, config, p, border)
        : _plainBody(p);

    if (onTap == null && onLongPress == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onLongPress: onLongPress,
      child: body,
    );
  }

  Widget _plainBody(GlassPalette p) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.plainCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.plainBorder),
        boxShadow: shadowless
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: p.shadow,
                  blurRadius: elevated ? 20 : 12,
                  offset: Offset(0, elevated ? 8 : 3),
                ),
              ],
      ),
      child: child,
    );
  }

  _LensPainter _lens(GlassPalette p, double phase) => _LensPainter(
        dark: p.dark,
        radius: radius - 1.2,
        edge: p.edgeHighlight,
        shade: p.lensShade,
        specular: p.specular,
        dispersion: p.dispersion,
        sheen: p.sheenAlpha,
        phase: phase,
        warm: p.causticWarm,
        cool: p.causticCool,
        strong: specular,
      );

  Widget _glassBody(
      BuildContext context, GlassConfig config, GlassPalette p, double border) {
    final outerRadius = BorderRadius.circular(radius);
    final innerRadius = BorderRadius.circular(math.max(0, radius - border));
    final clock = specular ? GlassClock.of(context) : null;

    // 光学层用 CustomPaint 的 painter + child 画在同一个渲染对象里，
    // 不用 Stack/Positioned 独立层：html renderer 会把独立层塞进 z-index:-1
    // 的 canvas，导致同容器里的文字被背景盖住。
    final inner = Padding(padding: padding, child: child);
    Widget content = Container(
      decoration: BoxDecoration(gradient: _thin(p.fill(tint), fillScale)),
      child: !showSheen
          ? inner
          : (clock == null
              ? CustomPaint(painter: _lens(p, _staticPhase(radius)), child: inner)
              : ValueListenableBuilder<double>(
                  valueListenable: clock,
                  builder: (_, double v, __) => CustomPaint(
                    painter: _lens(p, _phaseOf(v)),
                    child: inner,
                  ),
                )),
    );

    // 卡片级玻璃只做纯模糊；导航级（显式传 blur）才叠加透镜折射 ——
    // 一次透镜放大意味着整个背景被重新映射，几十张卡片都做太贵。
    final sigma = blur ?? config.blur;
    if (sigma > 0) {
      content = blur != null
          ? GlassSample(sigma: sigma, lens: config.lens, child: content)
          : GlassBlur(sigma: sigma, child: content);
    }

    return Container(
      padding: EdgeInsets.all(border),
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        gradient: p.rim(tint),
        boxShadow: shadowless
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: p.shadow,
                  blurRadius: elevated ? 36 : 24,
                  offset: Offset(0, elevated ? 14 : 8),
                ),
                BoxShadow(
                  color: p.glow,
                  blurRadius: 30,
                  spreadRadius: -12,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: ClipRRect(borderRadius: innerRadius, child: content),
    );
  }
}

/// AppBar 的玻璃底：整条覆盖（含 TabBar），底部一道会流动的镜面亮线。
class GlassBar extends StatelessWidget {
  const GlassBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);

    if (!config.enabled) {
      return Container(
        decoration: BoxDecoration(
          color: p.plainCard,
          border: Border(bottom: BorderSide(color: p.plainBorder)),
        ),
      );
    }

    final clock = GlassClock.of(context);
    Widget paintLayer = CustomPaint(
      painter: _BarPainter(p: p, phase: 0.12, sweep: false),
      child: const SizedBox.expand(),
    );
    if (clock != null) {
      paintLayer = ValueListenableBuilder<double>(
        valueListenable: clock,
        builder: (_, double v, __) => CustomPaint(
          painter: _BarPainter(p: p, phase: _phaseOf(v), sweep: true),
          child: const SizedBox.expand(),
        ),
      );
    }

    Widget content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[p.fillTop, p.fillMid, p.fillBottom],
        ),
        border: Border(bottom: BorderSide(color: p.glassLine, width: 1.0)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: p.shadow, blurRadius: 22, offset: const Offset(0, 5)),
        ],
      ),
      // 单层 CustomPaint（带 child），避免切出独立 canvas 层。
      child: paintLayer,
    );

    // 顶栏是大面积玻璃：走导航级采样（Web 上也开）。
    final double sigma = config.navBlur > 0 ? config.navBlur : config.blur;
    if (sigma > 0) {
      content = ClipRect(
        child: GlassSample(sigma: sigma, lens: config.lens, child: content),
      );
    }
    return content;
  }
}

/// 工具条玻璃：顶部柔光 + 内圈折射高光 + 沿底边流动的镜面亮线。
/// 三者合并在一个 painter 里，保证只占一个渲染层。
class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.p,
    required this.phase,
    required this.sweep,
  });

  final GlassPalette p;
  final double phase;
  final bool sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final a = p.sheenAlpha;

    final top = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height * 0.58),
      <Color>[Colors.white.withOpacity(a), Colors.white.withOpacity(0)],
    );
    canvas.drawRect(rect, Paint()..shader = top);

    // 内缘：一层暗折射带 + 一层亮高光线。
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.7), Radius.zero);
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.black.withOpacity(p.lensShade * 0.18),
    );
    final rimLight = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, size.height),
      <Color>[
        p.innerRim,
        Colors.white.withOpacity(0),
        p.innerRim.withOpacity(p.innerRim.alpha / 255 * 0.25),
      ],
      const <double>[0.0, 0.52, 1.0],
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = rimLight,
    );

    if (!sweep) return;
    final x = (phase * 1.4 - 0.2) * size.width;
    final g = ui.Gradient.linear(
      Offset(x - 150, 0),
      Offset(x + 150, 0),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(p.specular * 0.85),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 2.4, size.width, 2.4),
      Paint()..shader = g,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.p.dark != p.dark ||
      old.p.sheenAlpha != p.sheenAlpha ||
      old.p.lensShade != p.lensShade ||
      old.p.specular != p.specular ||
      old.phase != phase ||
      old.sweep != sweep;
}

/// 小玻璃药丸：时长、来源、名次、置顶等标签。默认胶囊形（iOS 控件语言）。
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
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    final Widget body;

    if (!config.enabled) {
      body = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: onDark
              ? Colors.black.withOpacity(0.68)
              : (tint ?? (p.dark ? AppColors.darkCard : Colors.white)),
          borderRadius: BorderRadius.circular(radius),
          border: tint == null && !onDark
              ? Border.all(color: p.plainBorder)
              : null,
        ),
        child: child,
      );
    } else {
      final List<Color> colors;
      final Color border;
      if (onDark) {
        colors = <Color>[
          const Color(0xFF20222C).withOpacity(0.44),
          const Color(0xFF080A10).withOpacity(0.52),
        ];
        border = Colors.white.withOpacity(0.66);
      } else {
        colors = <Color>[p.pillTop(tint), p.pillBottom(tint)];
        border = p.pillRim(tint);
      }
      body = Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          border: Border.all(color: border, width: 1.0),
          boxShadow: <BoxShadow>[
            BoxShadow(color: p.shadow, blurRadius: 8, offset: const Offset(0, 2)),
            BoxShadow(
              color: Colors.white.withOpacity(p.dark ? 0.06 : 0.30),
              blurRadius: 6,
              spreadRadius: -3,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            child,
            Positioned(
              left: radius > 100 ? 8 : 4,
              right: radius > 100 ? 8 : 4,
              top: 0.5,
              height: 1.0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(p.specular * 0.62),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

/// 玻璃芯片 / 按钮：分区筛选、排序、热词、主题选择、操作按钮共用。
/// 默认胶囊形，与 iOS 26 的按钮 / 开关 / 滑块语言一致。
class GlassChip extends StatelessWidget {
  const GlassChip({
    Key? key,
    required this.label,
    this.icon,
    this.leading,
    this.selected = false,
    this.onTap,
    this.radius = 999,
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
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    final dark = p.dark;
    final accent = tint ?? AppColors.pink;
    final Color labelColor = selected
        ? accent
        : (dark ? AppColors.darkText : AppColors.lightText);

    final Gradient gradient;
    final Color border;
    if (!config.enabled) {
      gradient = LinearGradient(colors: <Color>[
        selected ? accent.withOpacity(0.12) : p.plainCard,
        selected ? accent.withOpacity(0.12) : p.plainCard,
      ]);
      border = selected ? accent.withOpacity(0.5) : p.plainBorder;
    } else if (selected) {
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[p.selectedTop, p.selectedBottom],
      );
      border = p.selectedRim;
    } else {
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[p.pillTop(null), p.pillBottom(null)],
      );
      border = p.pillRim(null);
    }

    final Widget face = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: gradient,
        border: Border.all(color: border, width: 1.0),
        boxShadow: config.enabled
            ? <BoxShadow>[
                BoxShadow(
                    color: selected ? accent.withOpacity(0.24) : p.shadow,
                    blurRadius: selected ? 16 : 10,
                    offset: const Offset(0, 3)),
              ]
            : null,
      ),
      child: Stack(
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leading != null) ...<Widget>[leading!, const SizedBox(width: 6)],
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15, color: labelColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: labelStyle ??
                    TextStyle(
                      fontSize: 12.5,
                      color: labelColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
          if (config.enabled)
            Positioned(
              left: 10,
              right: 10,
              top: 0.6,
              height: 1.1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(p.specular * 0.72),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return GestureDetector(onTap: onTap, child: face);
  }
}

/// 圆形玻璃按钮（详情页封面中央的播放入口）：深玻璃 + 全周镜面高光环。
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
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: config.enabled
                ? <Color>[
                    const Color(0xFF4A4E68).withOpacity(0.30),
                    const Color(0xFF080A12).withOpacity(0.52),
                  ]
                : <Color>[
                    Colors.black.withOpacity(0.46),
                    Colors.black.withOpacity(0.46),
                  ],
          ),
          border: Border.all(
              color: Colors.white.withOpacity(config.enabled ? 0.90 : 0.78),
              width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 22,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: Colors.white.withOpacity(0.18),
                blurRadius: 10,
                spreadRadius: -3),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (config.enabled)
              Positioned.fill(
                child: CustomPaint(
                  painter: _LensPainter(
                    dark: true,
                    radius: size / 2,
                    edge: p.edgeHighlight,
                    shade: p.lensShade,
                    specular: p.specular,
                    dispersion: p.dispersion,
                    sheen: p.sheenAlpha,
                    phase: 0.12,
                    warm: p.causticWarm,
                    cool: p.causticCool,
                  ),
                ),
              ),
            Icon(icon, color: Colors.white, size: size * 0.55),
          ],
        ),
      ),
    );
  }
}

/// 小节标题前的发光玻璃竖条。
class GlassAccent extends StatelessWidget {
  const GlassAccent({Key? key, this.height = 15}) : super(key: key);

  final double height;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    if (!config.enabled) {
      return Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
            color: AppColors.pink, borderRadius: BorderRadius.circular(2)),
      );
    }
    return Container(
      width: 3.5,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFFFA8C4), AppColors.pink, Color(0xFFB85AF0)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: AppColors.pink.withOpacity(0.55),
              blurRadius: 8,
              offset: const Offset(0, 1)),
        ],
      ),
    );
  }
}

/// 半透明渐隐分隔线。
class GlassDivider extends StatelessWidget {
  const GlassDivider({Key? key, this.vertical = false, this.thickness = 1})
      : super(key: key);

  final bool vertical;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final color =
        p.dark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.90);
    return Container(
      width: vertical ? thickness : null,
      height: vertical ? null : thickness,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
          end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
          colors: <Color>[
            color.withOpacity(0),
            color,
            color.withOpacity(0),
          ],
        ),
      ),
    );
  }
}

class GlassDecorations {
  GlassDecorations._();

  /// TabBar 的玻璃胶囊指示器；关闭玻璃时退化为粉色下划线。
  static Decoration tabIndicator(BuildContext context) {
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    if (!config.enabled) {
      return const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.pink, width: 2.5)),
      );
    }
    return BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.white.withOpacity(p.dark ? 0.30 : 0.98),
          AppColors.pink.withOpacity(0.07),
          Colors.white.withOpacity(p.dark ? 0.12 : 0.86),
        ],
      ),
      border: Border.all(
          color: Colors.white.withOpacity(p.dark ? 0.42 : 0.98), width: 1.1),
      boxShadow: <BoxShadow>[
        BoxShadow(
            color: AppColors.pink.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 3)),
        BoxShadow(color: p.shadow, blurRadius: 8, offset: const Offset(0, 2)),
      ],
    );
  }

  /// 近乎全透的胶囊上，亮粉色文字对比度不足，浅色主题改用深粉。
  static Color tabLabelColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.pink
          : const Color(0xFFC4356B);

  static Color tabUnselectedLabelColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSub
          : const Color(0xFF5C6270);

  static EdgeInsets get tabIndicatorPadding =>
      const EdgeInsets.symmetric(horizontal: -14, vertical: 9);
}
