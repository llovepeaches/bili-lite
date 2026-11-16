import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/tokens.dart';
import '../core/nav_section.dart';
import '../core/theme.dart';

/// iOS 26 风格的液态玻璃底栏。
///
/// 视觉要点（对应参考图）：
/// 1. **整条底栏是一块厚玻璃**：背景模糊 + 内部近透明的浅色填充，
///    顶部一道亮白边、四周一圈渐变描边，靠光而不是靠底色定义形状；
/// 2. **液态流动的高光**：一条白色镜面亮带沿底栏上沿缓慢横向流动，
///    流动相位取自全局镜面时钟（[GlassClock]），整条底栏共享同一时钟，
///    因此和侧栏、顶栏的流光是同一个节奏，不会各走各的；
/// 3. **选中项是一枚「液态透镜」**：粉色渐变的圆角方块罩在图标上，
///    带外发光和内侧折射环，像一滴被光穿透的液体；
/// 4. **底栏固定不动**：滑动只发生在内容区，底栏本身不做位移，
///    仅通过透镜的位置与选中态颜色变化来指示当前页面。
class LiquidGlassDock extends StatelessWidget {
  const LiquidGlassDock({
    Key? key,
    required this.sections,
    required this.activeIndex,
    required this.onSelect,
    this.height = 62,
  }) : super(key: key);

  final List<AppSection> sections;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    final p = GlassPalette.of(context);
    final dark = p.dark;
    final clock = GlassClock.of(context);

    Widget surface = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
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
        borderRadius: BorderRadius.circular(29),
        child: Stack(
          children: <Widget>[
            // 液态流动高光：沿上沿横向游走的镜面亮带。
            Positioned.fill(
              child: clock == null
                  ? const _FlowHighlight(phase: 0.18, intensity: 1)
                  : ValueListenableBuilder<double>(
                      valueListenable: clock,
                      builder: (_, double v, __) =>
                          _FlowHighlight(phase: v, intensity: 1),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: _DockContent(
                sections: sections,
                activeIndex: activeIndex,
                onSelect: onSelect,
                height: height,
              ),
            ),
          ],
        ),
      ),
    );

    // 真实背景模糊：原生端开启，Web 的 html renderer 没有采样器，
    // 退化为渐变 + 高光模拟（配置里 blur 已经按平台区分）。
    if (config.enabled && config.blur > 0) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: config.blur,
            sigmaY: config.blur,
          ),
          child: surface,
        ),
      );
    }

    if (!config.enabled) {
      surface = Container(
        decoration: BoxDecoration(
          color: p.plainCard,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: p.plainBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: _DockContent(
            sections: sections,
            activeIndex: activeIndex,
            onSelect: onSelect,
            height: height,
          ),
        ),
      );
    }

    return SizedBox(height: height + 12, child: surface);
  }
}

/// 底栏内部：透镜指示器 + 图标文字。
class _DockContent extends StatelessWidget {
  const _DockContent({
    required this.sections,
    required this.activeIndex,
    required this.onSelect,
    required this.height,
  });

  final List<AppSection> sections;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;

    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = constraints.maxWidth / sections.length;
      final lensSize = math.min(itemWidth - 12, 44.0);

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            // 液态透镜：在图标位置滑动的圆角方块。
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
              children: List<Widget>.generate(sections.length, (i) {
                final section = sections[i];
                final selected = i == activeIndex;
                return SizedBox(
                  width: itemWidth,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => onSelect(i),
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

/// 沿底栏上沿横向流动的镜面亮带（液态感的主要来源）。
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
