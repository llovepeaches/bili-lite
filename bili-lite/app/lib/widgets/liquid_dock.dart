import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/nav_section.dart';
import '../core/theme.dart';
import '../core/tokens.dart';

/// iOS 26 风格的液态玻璃底栏。
///
/// 结构是**双件式**（对齐 iOS 26 Safari / Books 的底栏）：
/// 左边一枚装着标签组的玻璃胶囊，右边一枚**浮起的独立圆形按钮**。
/// 「搜索」属于后者 —— 它从胶囊里分出来，固定在最右侧，
/// 既不跟标签挤在同一条玻璃里，也不参与标签组的排序。
///
/// 视觉要点（对应参考图）：
/// 1. **胶囊是一块厚玻璃**：背景模糊 + 内部近透明的浅色填充，
///    顶部一道亮白边、四周一圈渐变描边，靠光而不是靠底色定义形状；
/// 2. **液态流动的高光**：一条白色镜面亮带沿胶囊上沿缓慢横向流动，
///    流动相位取自全局镜面时钟（[GlassClock]），整条底栏共享同一时钟，
///    因此和侧栏、顶栏的流光是同一个节奏，不会各走各的；
/// 3. **独立按钮是一枚圆玻璃**：同样的镜面语言，但高光绕着**圆周**游走，
///    选中时整枚按钮被粉色透镜点亮，像一颗被光穿透的液滴；
/// 4. **底栏固定不动**：滑动只发生在内容区，底栏本身不做位移，
///    仅通过透镜的位置与选中态颜色变化来指示当前页面。
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
    final p = GlassPalette.of(context);
    final clock = GlassClock.of(context);

    // 胶囊：标签组挤在同一条厚玻璃里。
    // 只留横向内边距 —— 纵向由内容自己占满胶囊高度，
    // 否则图标 + 文字会被挤出一截（图标 40 + 文字 12 + 间距 3 ≈ 55 < 62）。
    final Widget capsule = _GlassShell(
      radius: capsuleHeight / 2,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      flow: clock == null
          ? const _FlowHighlight(phase: 0.18, intensity: 1)
          : ValueListenableBuilder<double>(
              valueListenable: clock,
              builder: (_, double v, __) => _FlowHighlight(phase: v, intensity: 1),
            ),
      child: _CapsuleContent(
        tabs: tabs,
        active: active,
        onSelect: onSelect,
        height: capsuleHeight,
      ),
    );

    // 独立圆形按钮：搜索。
    Widget? button;
    if (standalone.isNotEmpty) {
      button = _StandaloneButton(
        section: standalone.first,
        selected: active == standalone.first,
        size: buttonSize,
        phase: clock == null ? 0.18 : null,
        clock: clock,
        onTap: () => onSelect(standalone.first),
      );
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: capsule),
        if (button != null) ...<Widget>[
          const SizedBox(width: 10),
          button,
        ],
      ],
    );

    Widget surface = SizedBox(
      height: math.max(capsuleHeight, buttonSize),
      child: row,
    );

    if (!config.enabled) {
      // 玻璃总开关关掉：退化成两片不透明卡片，但双件式结构保留。
      surface = Row(
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
                color: standalone.first == active
                    ? AppColors.pink
                    : context.subTextColor,
              ),
            ),
          ],
        ],
      );
    }

    return SizedBox(height: math.max(capsuleHeight, buttonSize) + 12, child: surface);
  }
}

/// 玻璃外壳：填充 + 描边 + 阴影 + 可选的流动高光。
///
/// 胶囊和独立按钮共用它，只是圆角不同（胶囊是长条、按钮是整圆）。
/// 每一件玻璃各自带一层 `BackdropFilter` —— 两件玻璃是分开的实体，
/// 背景模糊也应该各自贴着自己的轮廓，而不是糊成一整块。
class _GlassShell extends StatelessWidget {
  const _GlassShell({
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.shape = BoxShape.rectangle,
    this.flow,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final BoxShape shape;

  /// 叠在玻璃内部的高光层（胶囊用横向流动亮带，按钮用绕圆周的弧）。
  final Widget? flow;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final config = GlassTheme.of(context);
    final dark = p.dark;
    final borderRadius = BorderRadius.circular(radius);

    Widget body = Container(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : borderRadius,
        // 顶部亮、底部略暗，模拟厚玻璃受光。
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? <Color>[
                  Colors.white.withOpacity(0.13),
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.08),
                ]
              : <Color>[
                  Colors.white.withOpacity(0.72),
                  Colors.white.withOpacity(0.44),
                  Colors.white.withOpacity(0.58),
                ],
        ),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.30)
              : Colors.white.withOpacity(0.92),
          width: 1.1,
        ),
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
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: <Widget>[
            if (flow != null) Positioned.fill(child: flow!),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    // 真实背景模糊：原生端开启，Web 的 html renderer 没有采样器，
    // 退化为渐变 + 高光模拟（配置里 blur 已经按平台区分）。
    if (config.enabled && config.blur > 0) {
      body = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: config.blur,
            sigmaY: config.blur,
          ),
          child: body,
        ),
      );
    }

    return body;
  }
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

    final activeIndex = active == null ? -1 : tabs.indexOf(active!);

    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = constraints.maxWidth / tabs.length;
      final lensSize = math.min(itemWidth - 12, 44.0);

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
                final selected = section == active;
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

/// 底栏右侧的独立圆形玻璃按钮（搜索）。
///
/// 与胶囊是两件独立的玻璃：有自己的高光循环（绕圆周流动），
/// 选中时整枚按钮被粉色透镜点亮。
class _StandaloneButton extends StatelessWidget {
  const _StandaloneButton({
    required this.section,
    required this.selected,
    required this.size,
    required this.onTap,
    this.clock,
    this.phase,
  });

  final AppSection section;
  final bool selected;
  final double size;
  final VoidCallback onTap;
  final ValueNotifier<double>? clock;
  final double? phase;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;
    final sub = context.subTextColor;

    // 高光绕着圆周游走，跟胶囊里的横向流动是同一套镜面语言。
    final Widget flow = clock == null
        ? _CircularFlow(phase: phase ?? 0.18)
        : ValueListenableBuilder<double>(
            valueListenable: clock!,
            builder: (_, double v, __) => _CircularFlow(phase: v),
          );

    Widget content = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // 选中态：整枚按钮透出粉色液体。
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
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
              ),
            ),
          ),
        Icon(
          selected ? section.selectedIcon : section.icon,
          size: 22,
          color: selected ? AppColors.pink : sub,
        ),
      ],
    );

    Widget button = _GlassShell(
      radius: size / 2,
      shape: BoxShape.circle,
      flow: flow,
      child: SizedBox(
        width: size,
        height: size,
        child: content,
      ),
    );

    if (selected) {
      // 选中时按钮整体微微放大，像被"点亮"浮起来。
      button = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.pink.withOpacity(dark ? 0.42 : 0.32),
              blurRadius: 18,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: button,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: button,
    );
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
    final radius = size.width / 2;

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
