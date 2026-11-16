import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/nav_section.dart';
import '../core/theme.dart';
import '../core/tokens.dart';
import 'glass_press.dart';
import 'glass_sample.dart';

/// iOS 26 风格的液态玻璃底栏。
///
/// 结构是**双件式**（对齐 iOS 26 Safari / Books 的底栏）：
/// 左边一枚装着标签组的玻璃胶囊，右边一枚**浮起的独立圆形按钮**。
/// 「搜索」属于后者 —— 它从胶囊里分出来，固定在最右侧，
/// 既不跟标签挤在同一条玻璃里，也不参与标签组的排序。
///
/// 光学结构对齐 Compose 的 `rememberLayerBackdrop` 写法：
///
/// ```kotlin
/// val 背景 = rememberLayerBackdrop { drawRect(背景颜色); drawContent() }
/// 主导航主机(修饰符 = 修饰符.layerBackdrop(背景))
/// 盒子(背景 = 背景, shape = { CircleShape }, 影响 = { Blur(4f); Lens(16f, 32f) })
/// 盒子(背景 = 背景, shape = { 连续胶囊 }, 影响 = { Blur(4f); Lens(16f, 32f) })
/// ```
///
/// 翻译到 Flutter 是这样一套结构：
///
/// 1. **共享同一 backdrop**：整条底栏只做**一次**背景采样 ——
///    一层 `BackdropFilter` 覆盖两件玻璃的并集，模糊后的画面被
///    `ClipPath` 裁成「胶囊 ∪ 圆形」的形状。两件玻璃因此看到的是
///    **完全相同**的一份背景，而不是各自采到对方（实测：兄弟采样会污染）。
/// 2. **各自透镜**：两件玻璃在共享的模糊结果上再各套一层透镜矩阵，
///    支点各在自身中心，等效 Compose 里每件玻璃各自的 `Lens(16, 32)`。
/// 3. **表面层**：折射之上铺白色半透明层；再叠一层 `BlendMode.hue`
///    的色相染色（Compose 的 `drawRect(tint, Hue)`）。
/// 4. **液态流动的高光**：一条白色镜面亮带沿胶囊上沿缓慢横向流动，
///    相位取自全局镜面时钟（[GlassClock]），整条底栏共享同一时钟。
/// 5. **按压回弹**：圆形按钮按下时用弹簧放大（`ratio 0.5 / stiffness 300`），
///    松手回弹，是液态玻璃最容易被感知到的「手感」。
class LiquidGlassDock extends StatelessWidget {
  const LiquidGlassDock({
    Key? key,
    required this.tabs,
    required this.standalone,
    required this.active,
    required this.onSelect,
    this.capsuleHeight = 62,
    this.buttonSize = 58,
  }) : super(key: key);

  /// 胶囊内的标签组（可排序）。
  final List<AppSection> tabs;

  /// 底栏右侧的独立入口（固定在最右）。
  final List<AppSection> standalone;

  /// 当前选中的入口；为 null 表示还没有选中任何一项。
  final AppSection? active;

  final ValueChanged<AppSection> onSelect;

  /// 胶囊高度。
  final double capsuleHeight;

  /// 独立圆形按钮直径。
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    final double rowHeight = math.max(capsuleHeight, buttonSize);

    if (!config.enabled) {
      // 玻璃总开关关掉：退化成两片不透明卡片，但双件式结构保留。
      return SizedBox(
        height: rowHeight + 12,
        child: _PlainDock(
          tabs: tabs,
          standalone: standalone,
          active: active,
          onSelect: onSelect,
          capsuleHeight: capsuleHeight,
          buttonSize: buttonSize,
        ),
      );
    }

    return SizedBox(
      height: rowHeight + 12,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return _GlassDock(
            tabs: tabs,
            standalone: standalone,
            active: active,
            onSelect: onSelect,
            capsuleHeight: capsuleHeight,
            buttonSize: buttonSize,
            width: constraints.maxWidth,
            rowHeight: rowHeight,
          );
        },
      ),
    );
  }
}

/// 玻璃总开关关闭时的退化版本：两片不透明卡片。
class _PlainDock extends StatelessWidget {
  const _PlainDock({
    required this.tabs,
    required this.standalone,
    required this.active,
    required this.onSelect,
    required this.capsuleHeight,
    required this.buttonSize,
  });

  final List<AppSection> tabs;
  final List<AppSection> standalone;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double capsuleHeight;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final sub = context.subTextColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Container(
            height: capsuleHeight,
            decoration: BoxDecoration(
              color: p.plainCard,
              borderRadius: BorderRadius.circular(capsuleHeight / 2),
              border: Border.all(color: p.plainBorder),
            ),
            child: _CapsuleContent(
              tabs: tabs,
              active: active,
              onSelect: onSelect,
              height: capsuleHeight,
            ),
          ),
        ),
        if (standalone.isNotEmpty) ...<Widget>[
          const SizedBox(width: 10),
          Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              color: p.plainCard,
              shape: BoxShape.circle,
              border: Border.all(color: p.plainBorder),
            ),
            child: Icon(
              standalone.first == active
                  ? standalone.first.selectedIcon
                  : standalone.first.icon,
              size: 22,
              color: standalone.first == active ? AppColors.pink : sub,
            ),
          ),
        ],
      ],
    );
  }
}

/// 真·液态玻璃底栏：共享 backdrop + 各自透镜 + 表面层 + 流动高光。
///
/// 布局用 `Stack` 而不是 `Row`，因为「共享 backdrop」要求把两件玻璃
/// 放进同一个被裁剪的采样层里，而 `Row` 没法给出两件玻璃的精确矩形。
///
/// 几何计算放在一块**画布**上：画布比底栏本身大出一圈（[_pad]），
/// 这样按压时放大的圆形玻璃不会溢出底栏的边界而被裁掉。
class _GlassDock extends StatefulWidget {
  const _GlassDock({
    required this.tabs,
    required this.standalone,
    required this.active,
    required this.onSelect,
    required this.capsuleHeight,
    required this.buttonSize,
    required this.width,
    required this.rowHeight,
  });

  final List<AppSection> tabs;
  final List<AppSection> standalone;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double capsuleHeight;
  final double buttonSize;
  final double width;
  final double rowHeight;

  /// 两件玻璃之间的间隙。
  static const double _gap = 10;

  @override
  State<_GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<_GlassDock> with SingleTickerProviderStateMixin {
  /// 画布四周留出的余量：按压放大时圆形玻璃的溢出部分仍留在画布里。
  static const double _pad = 14;

  /// 圆形玻璃按压时的弹簧回弹。
  late final GlassPress _press = GlassPress(vsync: this);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 弹簧每帧都变，几何（放大的圆形、并集裁剪路径）要跟着重算，
    // 所以整块底栏挂在 AnimatedBuilder 上。
    return AnimatedBuilder(
      animation: _press.controller,
      builder: (BuildContext context, Widget? child) =>
          _buildDock(context, _press.progress),
    );
  }

  Widget _buildDock(BuildContext context, double progress) {
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    final clock = GlassClock.of(context);
    final dark = p.dark;
    final sub = context.subTextColor;

    final bool hasButton = widget.standalone.isNotEmpty;
    final double capsuleWidth = hasButton
        ? math.max(0, widget.width - _GlassDock._gap - widget.buttonSize)
        : widget.width;

    // 画布坐标 = 底栏坐标 + _pad。
    final Rect capsuleRect = Rect.fromLTWH(
      _pad,
      _pad + (widget.rowHeight - widget.capsuleHeight) / 2,
      capsuleWidth,
      widget.capsuleHeight,
    );

    // 圆形玻璃：按压时按弹簧进度放大（Compose 的
    // `maxScale = (size.width + 16dp) / size.width`）。
    final double maxScale = (widget.buttonSize + 16) / widget.buttonSize;
    final double scale = 1 + (maxScale - 1) * progress;
    final double circleSize = widget.buttonSize * scale;

    final Rect? circleRect = hasButton
        ? Rect.fromCenter(
            center: Offset(
              _pad + widget.width - widget.buttonSize / 2,
              _pad + widget.rowHeight / 2,
            ),
            width: circleSize,
            height: circleSize,
          )
        : null;

    // 胶囊 + 圆形的并集：共享采样层只在这块形状内可见。
    final Path union = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          capsuleRect,
          Radius.circular(widget.capsuleHeight / 2),
        ),
      );
    if (circleRect != null) {
      union.addOval(circleRect);
    }

    // ---- 胶囊的表面层与内容 ----
    final Widget capsuleFlow = clock == null
        ? const _FlowHighlight(phase: 0.18, intensity: 1)
        : ValueListenableBuilder<double>(
            valueListenable: clock,
            builder: (_, double v, __) => _FlowHighlight(phase: v, intensity: 1),
          );

    final Widget capsuleSurface = _GlassSurface(
      circle: false,
      gradient: _surfaceGradient(dark, sampled: true),
      hue: config.hue,
      hueAlpha: config.hueAlpha,
      hueMix: config.hueMix,
      flow: capsuleFlow,
    );

    final Widget capsuleContent = _CapsuleContent(
      tabs: widget.tabs,
      active: widget.active,
      onSelect: widget.onSelect,
      height: widget.capsuleHeight,
    );

    // ---- 圆形按钮的表面层与内容 ----
    Widget? circleContent;
    if (circleRect != null && widget.standalone.isNotEmpty) {
      final AppSection section = widget.standalone.first;
      final bool selected = widget.active == section;

      final Widget circleFlow = clock == null
          ? _CircularFlow(phase: 0.18)
          : ValueListenableBuilder<double>(
              valueListenable: clock,
              builder: (_, double v, __) => _CircularFlow(phase: v),
            );

      final Widget circleSurface = _GlassSurface(
        circle: true,
        gradient: _surfaceGradient(dark, sampled: true),
        hue: config.hue,
        hueAlpha: config.hueAlpha,
        hueMix: config.hueMix,
        flow: circleFlow,
      );

      // 选中态：整枚按钮透出粉色液体。
      final Widget selectedWash = selected
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppColors.pink.withOpacity(dark ? 0.46 : 0.38),
                    AppColors.pink.withOpacity(dark ? 0.24 : 0.18),
                    const Color(0xFF9A7BFF).withOpacity(dark ? 0.30 : 0.20),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink();

      final Widget ring = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: dark
                ? Colors.white.withOpacity(0.30)
                : Colors.white.withOpacity(0.92),
            width: 1.1,
          ),
        ),
      );

      circleContent = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails details) => _press.press(),
        onTapUp: (TapUpDetails details) => _press.release(),
        onTapCancel: () => _press.release(),
        onTap: () => widget.onSelect(widget.standalone.first),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(child: circleSurface),
            selectedWash,
            ring,
            Icon(
              selected ? section.selectedIcon : section.icon,
              size: 22,
              color: selected ? AppColors.pink : sub,
            ),
          ],
        ),
      );
    }

    final double canvasWidth = widget.width + _pad * 2;
    final double canvasHeight = widget.rowHeight + _pad * 2;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // 画布：整体往左上挪 _pad，让玻璃有溢出空间。
        Positioned(
          left: -_pad,
          top: -_pad,
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 阴影层：画在玻璃之下。玻璃的 backdrop 会采样到它 ——
              // 这正好让玻璃边缘带上一点被环境压暗的痕迹。
              _ShadowBox(rect: capsuleRect, circle: false),
              if (circleRect != null) _ShadowBox(rect: circleRect, circle: true),

              // 共享 backdrop：整条底栏只做**一次**背景采样。
              //
              // 一层模糊铺满并集的外接矩形，再用 ClipPath 裁成
              // 「胶囊 ∪ 圆形」—— 于是两件玻璃看到的是同一份画面，
              // 彼此之间不会互相采样（实测：重叠的兄弟玻璃会吃进对方的像素）。
              Positioned.fill(
                child: ClipPath(
                  clipper: _UnionClipper(union),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: config.navBlur,
                      sigmaY: config.navBlur,
                    ),
                    child: Stack(
                      children: <Widget>[
                        // 每件玻璃在共享的模糊结果上再套一层自己的透镜。
                        Positioned.fromRect(
                          rect: capsuleRect,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(widget.capsuleHeight / 2),
                            child: GlassSample(
                              // 模糊已经在共享层做过，这里只留透镜。
                              sigma: 0.01,
                              lens: config.lens,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        if (circleRect != null)
                          Positioned.fromRect(
                            rect: circleRect,
                            child: ClipOval(
                              child: GlassSample(
                                sigma: 0.01,
                                lens: config.lens,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 表面层与内容：画在玻璃之上（这一层不参与采样）。
              Positioned.fromRect(
                rect: capsuleRect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.capsuleHeight / 2),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: capsuleSurface),
                      Positioned.fill(child: capsuleContent),
                    ],
                  ),
                ),
              ),
              if (circleRect != null && circleContent != null)
                Positioned.fromRect(
                  rect: circleRect,
                  child: ClipOval(child: circleContent),
                ),
            ],
          ),
        ),

      ],
    );
  }
}

/// 玻璃表面层的渐变（顶部亮、底部略暗，模拟厚玻璃受光）。
Gradient _surfaceGradient(bool dark, {required bool sampled}) {
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: dark
        ? <Color>[
            Colors.white.withOpacity(sampled ? 0.10 : 0.13),
            Colors.white.withOpacity(sampled ? 0.04 : 0.05),
            Colors.white.withOpacity(sampled ? 0.07 : 0.08),
          ]
        : <Color>[
            Colors.white.withOpacity(sampled ? 0.34 : 0.72),
            Colors.white.withOpacity(sampled ? 0.16 : 0.44),
            Colors.white.withOpacity(sampled ? 0.26 : 0.58),
          ],
  );
}

/// 玻璃表面层：渐变染色 + 白色表面层 + Hue 色相染色 + 流动高光。
///
/// 绘制顺序对齐 Compose 的 `onDrawSurface`：
///
/// ```kotlin
/// drawRect(Color.White.copy(alpha = 0.5f))          // 白色表面层
/// drawRect(tint, blendMode = BlendMode.Hue)          // 色相染色
/// drawRect(tint.copy(alpha = 0.75f))                 // 染色叠加
/// ```
///
/// 其中 `BlendMode.hue` 取**源**的色相、**目标**的饱和度与明度。
/// 实测（原生 Linux Skia）：玻璃内画一个 Hue 混合的蓝色矩形，
/// 底下是红色背景时结果是 `(0, 97, 174)` —— 正是「蓝的色相 + 红的
/// 饱和度明度」，说明 Hue 确实作用在滤镜输出（backdrop）上。
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.circle,
    required this.gradient,
    required this.flow,
    this.hue,
    this.hueAlpha = 0,
    this.hueMix = 0,
  });

  final bool circle;
  final Gradient gradient;
  final Widget flow;

  /// 色相染色目标色；null 表示不染色。
  final Color? hue;

  /// 染色叠加层的不透明度。
  final double hueAlpha;

  /// `BlendMode.hue` 混合层自身的强度。
  final double hueMix;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    final Widget? hueLayer = (hue != null && (hueAlpha > 0 || hueMix > 0))
        ? _HueTintLayer(color: hue!, alpha: hueAlpha, mix: hueMix)
        : null;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(1000),
            gradient: gradient,
          ),
        ),
        // 白色表面层：等效 Compose 的 onDrawSurface。
        if (config.surface > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.white.withOpacity(config.surface),
            ),
          ),
        if (hueLayer != null) IgnorePointer(child: hueLayer),
        flow,
      ],
    );
  }
}

/// `BlendMode.hue` 的色相染色层。
///
/// 关键点：这个矩形必须画在**滤镜输出之上、同一画布之内**，
/// Hue 混合才会作用在被折射的背景上（而不是作用在一张空画布上）。
class _HueTintLayer extends StatelessWidget {
  const _HueTintLayer({
    required this.color,
    required this.alpha,
    required this.mix,
  });

  final Color color;
  final double alpha;

  /// Hue 混合层自身的强度（源色不透明度）。
  final double mix;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HueTintPainter(color: color, alpha: alpha, mix: mix),
      child: const SizedBox.expand(),
    );
  }
}

class _HueTintPainter extends CustomPainter {
  const _HueTintPainter({
    required this.color,
    required this.alpha,
    required this.mix,
  });

  final Color color;
  final double alpha;
  final double mix;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    // 先做色相替换：取源的色相、目标的饱和度与明度。
    canvas.drawRect(
      rect,
      Paint()
        // 半透明的染色源：Hue 混合只部分接管色相，背景的明暗层次还在。
        ..color = color.withOpacity(mix)
        ..blendMode = BlendMode.hue,
    );
    // 再叠一层薄薄的染色，把彩度补回来。
    canvas.drawRect(rect, Paint()..color = color.withOpacity(alpha));
  }

  @override
  bool shouldRepaint(covariant _HueTintPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.alpha != alpha ||
      oldDelegate.mix != mix;
}

/// 玻璃外侧的投影层。
class _ShadowBox extends StatelessWidget {
  const _ShadowBox({required this.rect, required this.circle});

  final Rect rect;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;

    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle
              ? null
              : BorderRadius.circular(rect.height / 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: dark
                  ? Colors.black.withOpacity(0.46)
                  : const Color(0xFF6E648F).withOpacity(0.16),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(dark ? 0.10 : 0.46),
              blurRadius: 10,
              spreadRadius: -4,
              offset: const Offset(0, -3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把共享采样层裁成「胶囊 ∪ 圆形」。
class _UnionClipper extends CustomClipper<Path> {
  const _UnionClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _UnionClipper oldClipper) => true;
}

/// 胶囊内部：透镜指示器 + 图标文字。
class _CapsuleContent extends StatelessWidget {
  const _CapsuleContent({
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.height,
  });

  final List<AppSection> tabs;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    if (tabs.isEmpty) return SizedBox(height: height);

    final int activeIndex = active == null ? -1 : tabs.indexOf(active!);

    return LayoutBuilder(builder: (context, constraints) {
      final double itemWidth = constraints.maxWidth / tabs.length;
      final double lensSize = math.min(itemWidth - 12, 44.0);

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            // 液态透镜：在图标位置滑动的圆角方块。
            if (activeIndex >= 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                left: activeIndex * itemWidth + (itemWidth - lensSize) / 2,
                top: 0,
                width: lensSize,
                height: lensSize,
                child: LiquidLens(size: lensSize),
              ),
            Row(
              children: List<Widget>.generate(tabs.length, (i) {
                final section = tabs[i];
                final bool selected = section == active;
                return SizedBox(
                  width: itemWidth,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onSelect(section),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          height: lensSize,
                          child: Icon(
                            selected ? section.selectedIcon : section.icon,
                            size: 22,
                            color: selected ? AppColors.pink : sub,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          section.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w500,
                            color: selected ? AppColors.pink : sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      );
    });
  }
}

/// 选中项的液态透镜：粉色渐变 + 外发光 + 内侧折射高光。
///
/// 窄屏底栏与宽屏侧栏共用这一个组件，保证两种形态下的选中态是同一套视觉。
class LiquidLens extends StatelessWidget {
  const LiquidLens({Key? key, required this.size}) : super(key: key);

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.42),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.pink.withOpacity(dark ? 0.42 : 0.34),
            AppColors.pink.withOpacity(dark ? 0.22 : 0.16),
            const Color(0xFF9A7BFF).withOpacity(dark ? 0.26 : 0.18),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(dark ? 0.62 : 0.95),
          width: 1.1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.pink.withOpacity(dark ? 0.40 : 0.30),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(dark ? 0.18 : 0.60),
            blurRadius: 7,
            spreadRadius: -3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          // 上沿一道折射亮线：透镜顶部被环境光点亮。
          Positioned(
            left: size * 0.18,
            right: size * 0.18,
            top: 0.8,
            height: 1.1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withOpacity(0),
                      Colors.white.withOpacity(dark ? 0.62 : 0.98),
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
}

/// 沿玻璃上沿横向流动的镜面亮带（液态感的主要来源）。
class _FlowHighlight extends StatelessWidget {
  const _FlowHighlight({required this.phase, required this.intensity});

  final double phase;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    return CustomPaint(
      painter: _FlowPainter(
        phase: phase,
        intensity: intensity,
        sheen: p.sheenAlpha,
        specular: p.specular,
        dark: p.dark,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.phase,
    required this.intensity,
    required this.sheen,
    required this.specular,
    required this.dark,
  });

  final double phase;
  final double intensity;
  final double sheen;
  final double specular;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 上半部的斜向环境光：玻璃顶面受光。
    final top = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height * 0.55),
      <Color>[
        Colors.white.withOpacity(sheen * 0.9),
        Colors.white.withOpacity(0),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = top);

    // 流动亮带：沿水平方向缓慢游走的窄光斑。
    final travel = size.width + 260.0;
    final x = rect.left - 130.0 + (phase % 1.0) * travel;
    final band = ui.Gradient.linear(
      Offset(x - 110, 0),
      Offset(x + 110, size.height),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(specular * 0.30 * intensity),
        Colors.white.withOpacity(specular * 0.62 * intensity),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.34, 0.58, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = band);

    // 上沿一道会呼吸的亮线：亮带的落点。
    final line = ui.Gradient.linear(
      Offset(x - 90, 0),
      Offset(x + 90, 0),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(specular * 0.85 * intensity),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 1.8),
      Paint()..shader = line,
    );

    // 底部内阴影：玻璃厚度带来的暗边。
    final bottom = ui.Gradient.linear(
      Offset(0, size.height * 0.72),
      Offset(0, size.height),
      <Color>[
        Colors.black.withOpacity(0),
        Colors.black.withOpacity(dark ? 0.22 : 0.07),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = bottom);
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.phase != phase ||
      old.intensity != intensity ||
      old.sheen != sheen ||
      old.specular != specular ||
      old.dark != dark;
}

/// 绕圆周游走的镜面弧（独立圆形按钮的液态感）。
///
/// 实现上用「旋转画布 + 裁剪到椭圆」来模拟光斑绕圈走，
/// 避开 `Path.computeMetrics()` —— Flutter Web 的 html renderer 会把
/// 抽出来的 path 切到独立的 canvas 层上，反而把图标盖住。
class _CircularFlow extends StatelessWidget {
  const _CircularFlow({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    return CustomPaint(
      painter: _CircularFlowPainter(
        phase: phase,
        sheen: p.sheenAlpha,
        specular: p.specular,
        dark: p.dark,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _CircularFlowPainter extends CustomPainter {
  _CircularFlowPainter({
    required this.phase,
    required this.sheen,
    required this.specular,
    required this.dark,
  });

  final double phase;
  final double sheen;
  final double specular;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final double radius = size.width / 2;

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // 玻璃顶面受光。
    final top = ui.Gradient.linear(
      Offset(center.dx, rect.top),
      Offset(center.dx, center.dy),
      <Color>[
        Colors.white.withOpacity(sheen * 0.85),
        Colors.white.withOpacity(0),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = top);

    // 一条绕着圆周跑的亮弧：把画布旋转，让线性渐变变成"绕圈的光斑"。
    canvas.translate(center.dx, center.dy);
    canvas.rotate((phase % 1.0) * 2 * math.pi);
    final arc = ui.Gradient.linear(
      Offset(-radius * 1.5, 0),
      Offset(radius * 1.5, 0),
      <Color>[
        Colors.white.withOpacity(0),
        Colors.white.withOpacity(specular * 0.34),
        Colors.white.withOpacity(specular * 0.68),
        Colors.white.withOpacity(0),
      ],
      const <double>[0.0, 0.32, 0.56, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(-radius * 1.6, -radius * 1.6, radius * 1.6, radius * 1.6),
      Paint()..shader = arc,
    );
    canvas.restore();

    // 底部内阴影：玻璃厚度带来的暗边。
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final bottom = ui.Gradient.linear(
      Offset(center.dx, center.dy),
      Offset(center.dx, rect.bottom),
      <Color>[
        Colors.black.withOpacity(0),
        Colors.black.withOpacity(dark ? 0.24 : 0.08),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = bottom);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircularFlowPainter old) =>
      old.phase != phase ||
      old.sheen != sheen ||
      old.specular != specular ||
      old.dark != dark;
}
