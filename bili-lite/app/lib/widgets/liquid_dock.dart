import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_theme.dart';
import '../core/nav_section.dart';
import '../core/theme.dart';
import '../core/tokens.dart';
import 'glass_drop.dart';
import 'glass_drop_motion.dart';
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
    this.compact = false,
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

  /// compact 模式：标签收起、底栏变矮。
  ///
  /// 对齐 iOS 26 的 `.tabBarMinimizeBehavior(.onScrollDown)` ——
  /// 向下滚动内容时底栏收起，把屏幕空间还给内容。
  final bool compact;

  /// 玻璃里那一份「折射像」标签的 key。
  ///
  /// 底栏上每个 tab 的文字会出现两次：一次在标签行里（真正可交互的那个），
  /// 一次在水滴玻璃底下（折射像，只是视觉）。
  /// 测试要精确定位标签行里的那个时，用这个 key 排除折射像。
  static Key get dropLabelKey => _DropContent.labelKey;

  @override
  Widget build(BuildContext context) {
    final config = GlassTheme.of(context);
    // compact 模式：胶囊压矮，标签收起只留图标。
    //
    // iOS 26 的 `.tabBarMinimizeBehavior(.onScrollDown)` 就是这个效果 ——
    // 底栏缩到只剩一排图标，把纵向空间还给内容。
    final double capsuleH = compact ? capsuleHeight * 0.78 : capsuleHeight;
    final double button = compact ? buttonSize * 0.86 : buttonSize;
    final double rowHeight = math.max(capsuleH, button);

    if (!config.enabled) {
      // 玻璃总开关关掉：退化成两片不透明卡片，但双件式结构保留。
      return SizedBox(
        height: rowHeight + 12,
        child: _PlainDock(
          tabs: tabs,
          standalone: standalone,
          active: active,
          onSelect: onSelect,
          capsuleHeight: capsuleH,
          buttonSize: button,
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
            capsuleHeight: capsuleH,
            buttonSize: button,
            width: constraints.maxWidth,
            rowHeight: rowHeight,
            compact: compact,
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
            child: _PlainCapsuleContent(
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
    this.compact = false,
  });

  final List<AppSection> tabs;
  final List<AppSection> standalone;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double capsuleHeight;
  final double buttonSize;
  final double width;
  final double rowHeight;

  /// compact 模式：标签收起，底栏变矮（滚动时用）。
  final bool compact;

  /// 两件玻璃之间的间隙。
  static const double _gap = 10;

  @override
  State<_GlassDock> createState() => _GlassDockState();
}

/// 注意用 [TickerProviderStateMixin] 而不是 `SingleTickerProviderStateMixin`：
/// 这个 State 里有两个 ticker 源 —— 圆形玻璃的按压弹簧 [GlassPress] 一个，
/// 水滴透镜的 [GlassDropMotion] 内部还有抬起/飞行两个控制器。
class _GlassDockState extends State<_GlassDock> with TickerProviderStateMixin {
  /// 画布四周留出的余量：按压放大时圆形玻璃的溢出部分仍留在画布里。
  static const double _pad = 14;

  /// 圆形玻璃按压时的弹簧回弹。
  late final GlassPress _press = GlassPress(vsync: this);

  /// 水滴透镜的运动模型（抬起 / 飞行 / 拉伸 / 擦洗）。
  late final GlassDropMotion _drop = GlassDropMotion(vsync: this);

  /// 拖动擦洗：按下时的 x。
  double _dragStartX = 0;

  /// 拖动擦洗：按下时水滴所在的位置（拖动是相对位移，不是绝对定位）。
  double _dragOriginX = 0;

  /// 当前是否处于「正在擦洗」状态。
  bool _dragging = false;

  /// 超过这个位移（逻辑像素）才算擦洗，否则算点击。
  static const double _scrubThreshold = 6;

  /// 擦洗是否启用（只有一个 tab 时没什么可擦的）。
  bool get _scrubEnabled => widget.tabs.length > 1;

  @override
  void initState() {
    super.initState();
    _syncDropToActive();
  }

  @override
  void didUpdateWidget(covariant _GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 选中项变了 → 水滴飞过去。
    if (oldWidget.active != widget.active) {
      _syncDropToActive();
    }
  }

  /// 把水滴对齐到当前选中的 tab。
  void _syncDropToActive() {
    final List<AppSection> tabs = widget.tabs;
    if (tabs.isEmpty) return;
    final int index = widget.active == null ? 0 : tabs.indexOf(widget.active!);
    _drop.travelTo(index < 0 ? 0 : index);
  }

  @override
  void dispose() {
    _press.dispose();
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 弹簧每帧都变，几何（放大的圆形、并集裁剪路径）要跟着重算，
    // 所以整块底栏挂在 AnimatedBuilder 上。
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_press.controller, _drop]),
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
      // 底栏**不染色相**。
      //
      // 页面里的玻璃卡片用冷蓝 Hue 染色是为了让玻璃「像一块有色的实体」，
      // 但系统底栏不行：iOS 的 tab bar 在浅色模式是**纯乳白**、
      // 深色模式是**中性烟熏灰**，两者都不偏色相。
      //
      // 关键在于 `BlendMode.hue` 取的是**源**的色相 —— 拿饱和蓝
      // `#0088FF` 去混一块近白的乳白基底，结果是把白压成冷灰蓝，
      // 底栏于是「看着发暗」。去掉这一层，乳白才真的是乳白。
      hue: null,
      hueAlpha: 0,
      hueMix: 0,
      flow: capsuleFlow,
    );

    final Widget capsuleContent = _CapsuleContent(
      tabs: widget.tabs,
      active: widget.active,
      onSelect: widget.onSelect,
      height: widget.capsuleHeight,
      motion: _drop,
      compact: widget.compact,
    );

    // ---- 拖动擦洗 ----
    //
    // iOS 26 允许**按住沿底栏拖动**，水滴跟手移动，松手落到最近的那个 tab。
    // 这里用 `Listener` 而不是 `GestureDetector`：
    // `GestureDetector` 的 onPanStart 会和子级 Icon 的 onTap 抢手势，
    // 而 `Listener` 在原始指针事件层面工作，能保证「拖动优先、点击其次」。
    //
    // 判定阈值 6px：小于它算点击（交给子级的 onTap），大于它算擦洗。
    final Widget scrubbableCapsule = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        _dragStartX = e.localPosition.dx;
        _dragOriginX = _drop.x;
        _dragging = false;
      },
      onPointerMove: (PointerMoveEvent e) {
        if (!_scrubEnabled) return;
        if (!_dragging) {
          if ((e.localPosition.dx - _dragStartX).abs() < _scrubThreshold) {
            return;
          }
          _dragging = true;
          _drop.pressLift();
        }
        // 把位移换算成胶囊内的局部坐标，交给水滴跟手。
        _drop.scrubTo(_dragOriginX + (e.localPosition.dx - _dragStartX));
      },
      onPointerUp: (PointerUpEvent e) {
        if (_dragging) {
          _dragging = false;
          // 松手：落到最近的 tab，并通知外层切换。
          _drop.scrubRelease();
          final int idx = _drop.index;
          if (idx >= 0 && idx < widget.tabs.length) {
            final AppSection section = widget.tabs[idx];
            if (section != widget.active) widget.onSelect(section);
          }
        }
      },
      onPointerCancel: (PointerCancelEvent e) {
        if (_dragging) {
          _dragging = false;
          _drop.scrubRelease();
        }
      },
      child: capsuleContent,
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
        // 同胶囊：不染色相，保持中性乳白 / 烟熏灰。
        hue: null,
        hueAlpha: 0,
        hueMix: 0,
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
            // Liquid Glass v2 的暗边。
            const Positioned.fill(child: _DarkenedEdge(circle: true)),
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
                      Positioned.fill(child: scrubbableCapsule),
                      // Liquid Glass v2 的暗边：压在最上面，把形状「勒」出来。
                      Positioned.fill(child: const _DarkenedEdge(circle: false)),
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

/// 玻璃表面层的渐变。
///
/// iOS 26/27 的底栏玻璃有两种材质（Apple 内部叫 *milky* 与 *smoked*）：
///
/// * **浅色模式 = milky（乳白玻璃）**：一层**不透明偏白**的基底，
///   底下内容只透出模糊后的色块，透不透得过去不重要 ——
///   重要的是它看起来像一块**磨砂的牛奶玻璃**，而不是一块透明塑料片。
/// * **深色模式 = smoked（烟熏玻璃）**：一层**偏黑**的基底，
///   底下内容同样只透出模糊色块。
///
/// 这跟「通透档」的思路是反的：通透档追求「内部近乎全透，玻璃只由边缘定义形状」，
/// 而 iOS 的系统底栏恰恰是**先保证可读性**（内容不透过去），
/// 再用折射和边缘高光表现玻璃感。
///
/// 底栏是**系统级 chrome**，内容要从它下面穿过去 —— 这时「可读」优先于「通透」。
/// 所以这里给底栏单独一套材质，不跟页面里的玻璃卡片共用。
Gradient _surfaceGradient(bool dark, {required bool sampled}) {
  if (dark) {
    // smoked：偏黑的基底 + 一点点顶部受光。
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        const Color(0xFF32323A).withOpacity(sampled ? 0.70 : 0.86),
        const Color(0xFF232329).withOpacity(sampled ? 0.76 : 0.92),
        const Color(0xFF2A2A31).withOpacity(sampled ? 0.68 : 0.84),
      ],
    );
  }
  // milky：乳白基底 + 顶部更亮（受光面）。
  //
  // 不透明度给得很高（0.90~0.96）——「乳白」的意思本来就是**不透明**，
  // 底下只透出模糊后的浅色块，而不是让页面内容整片透上来。
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      const Color(0xFFFFFFFF).withOpacity(sampled ? 0.92 : 0.97),
      const Color(0xFFF6F7FA).withOpacity(sampled ? 0.90 : 0.95),
      const Color(0xFFFBFBFD).withOpacity(sampled ? 0.90 : 0.96),
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

/// Liquid Glass v2 的「暗边」。
///
/// iOS 27 给玻璃加了一圈**变暗的边缘**（*darkened edge*），
/// 配合更亮的镜面高光，玻璃才有立体感 —— 否则它只是一张半透明的色片。
///
/// 实现上用**内阴影**：从形状内侧往里压一圈黑，宽度很窄。
///
/// 浅色模式下的强度刻意压得很低 —— 乳白玻璃的边缘本来就很淡，
/// 暗边一重就变成了一圈灰线，看着像描边而不是玻璃。
class _DarkenedEdge extends StatelessWidget {
  const _DarkenedEdge({required this.circle});

  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final dark = p.dark;

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(1000),
          border: Border.all(
            color: Colors.black.withOpacity(dark ? 0.34 : 0.10),
            width: 1.4,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.26 : 0.07),
              blurRadius: 4,
              spreadRadius: -2,
              offset: const Offset(0, 1),
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

/// 玻璃总开关关闭时的胶囊内容：只有图标 + 文字，没有水滴透镜。
///
/// 玻璃材质关掉时再放一颗「水滴」是自相矛盾的 —— 水滴本身就是玻璃，
/// 没有玻璃就不该有水滴。所以这里退回到最朴素的选中态：一个半透明圆角块。
class _PlainCapsuleContent extends StatelessWidget {
  const _PlainCapsuleContent({
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
    final sub = AppTextColor.tertiary(context);
    if (tabs.isEmpty) return SizedBox(height: height);

    final int activeIndex = active == null ? -1 : tabs.indexOf(active!);

    return LayoutBuilder(builder: (context, constraints) {
      final double itemWidth = constraints.maxWidth / tabs.length;
      final double lensSize =
          math.min(math.min(itemWidth - 8, 44.0), height - 15);

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            if (activeIndex >= 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: activeIndex * itemWidth + (itemWidth - lensSize) / 2,
                top: (height - lensSize - 15) / 2,
                width: lensSize,
                height: lensSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(lensSize * 0.42),
                    color: AppColors.pink.withOpacity(0.16),
                  ),
                ),
              ),
            Row(
              children: List<Widget>.generate(tabs.length, (i) {
                final section = tabs[i];
                final bool selected = section == active;
                return SizedBox(
                  width: itemWidth,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(section),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          height: lensSize,
                          child: Center(
                            child: Icon(
                              selected ? section.selectedIcon : section.icon,
                              size: (lensSize * 0.52).clamp(16.0, 24.0),
                              color: selected ? AppColors.pink : sub,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          section.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.micro,
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

/// 胶囊内部：iOS 式水滴透镜 + 图标文字。
///
/// 这一版把旧版的「粉色圆角方块指示器」换成了 iOS 26/27 的**玻璃水滴**：
///
/// * 水滴按下时**抬起**（底盘淡出、变成通透的玻璃珠）；
/// * 飞行时按距离**拉伸**，落位时**压扁**再回弹；
/// * 玻璃下面的图标和文字被**放大**（折射效果，不是选中态变大）；
/// * 按住沿底栏**拖动**可以擦洗水滴，松手落到最近的 tab。
///
/// 运动参数都在 [GlassDropMotion] 里，这里只负责把状态映射成几何。
class _CapsuleContent extends StatelessWidget {
  const _CapsuleContent({
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.height,
    required this.motion,
    required this.compact,
  });

  final List<AppSection> tabs;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double height;

  /// 水滴运动模型。
  final GlassDropMotion motion;

  /// compact 模式：标签收起，只留图标（iOS 26 的
  /// `.tabBarMinimizeBehavior(.onScrollDown)`）。
  final bool compact;

  /// 文字标签的预留高度（字号 10.5、行高 1.1）。
  static const double _labelHeight = 12.0;

  /// 图标与标签之间的间距。
  static const double _labelGap = 3.0;

  @override
  Widget build(BuildContext context) {
    final sub = AppTextColor.tertiary(context);
    if (tabs.isEmpty) return SizedBox(height: height);

    return LayoutBuilder(builder: (context, constraints) {
      final double itemWidth = constraints.maxWidth / tabs.length;
      // 透镜尺寸跟着可用宽度走，但要留出上下空间给图标 + 文字标签。
      //
      // 上一版这里固定 `min(itemWidth - 12, 44)`，忽略了「图标 + 标签」需要
      // 竖向空间：当底栏被右侧圆形按钮挤窄时，itemWidth 变小，透镜跟着变小，
      // 但图标仍是硬编码的 22px —— 两者一旦对不齐，图标就会溢出透镜，
      // 再叠加 Column 溢出，图标和文字就叠在一起了
      // （见 `docs/preview/50-r7-home.png` 底部首页/搜索/空间那一排）。
      //
      // 现在把三者的尺寸绑定在一起算：透镜 = 图标 + 内边距，
      // 图标随透镜等比缩放，且保证「透镜 + 标签」的总高不超过可用高度。
      final double available = height - _labelHeight - _labelGap;
      final double lensSize =
          math.min(math.min(itemWidth - 8, 44.0), math.max(24.0, available));
      final double iconSize = (lensSize * 0.52).clamp(16.0, 24.0);

      // compact 模式：标签淡出后，透镜可以占更多高度。
      final double labelHeight = compact ? 0 : _labelHeight;
      final double labelGap = compact ? 0 : _labelGap;

      // 水滴的尺寸：**只罩住图标**，不罩住文字标签。
      //
      // 这是 iOS 的做法 —— 玻璃「水滴」是一颗落在图标上的珠子，
      // 文字标签在珠子**下面**，被染色成选中色但不被玻璃罩住。
      //
      // 形状是**竖着的胶囊**（高 > 宽），读起来才像「一滴水」；
      // 正圆读起来像「一个圆按钮」。
      //
      // 尺寸围绕**图标**算，而不是围绕旧的 lensSize：
      // 图标 22~24px，水滴 = 图标 + 上下各 7px 内边距 → 约 36×38。
      //
      // 关键约束：水滴底边必须**留出标签的空间**，
      // 否则玻璃珠会压到文字上（第一版就是这个毛病：
      // `dropHeight = lensSize + 8` 里 lensSize 最大 44，
      // 水滴高 52 而底栏可用高度才 50，珠子直接盖住了「首页」两个字）。
      final double dropHeight = math.min(
        iconSize + 14,
        math.max(28.0, height - labelHeight - labelGap - 2),
      );
      final double dropWidth = math.min(
        dropHeight * 0.86,
        math.min(itemWidth - 12, 44.0),
      );

      // 把每个 tab 的中心 x 交给运动模型 —— 拖动擦洗要靠它算最近目标。
      //
      // 注意这里必须**在 build 里更新**：胶囊宽度会随屏幕宽度变化，
      // 缓存下来的中心坐标一旦过期，擦洗就会落到错误的 tab 上。
      final List<double> centers = List<double>.generate(
        tabs.length,
        (int i) => i * itemWidth + itemWidth / 2,
      );
      motion.setCenters(centers);

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            // ---- 水滴透镜 ----
            //
            // 位置由运动模型给出（飞行中会连续变化），
            // 形状由 stretch 给出（飞行中纵向拉长、落位时压扁）。
            Positioned(
              left: motion.x - dropWidth / 2,
              top: (height - dropHeight - labelHeight - labelGap) / 2,
              width: dropWidth,
              height: dropHeight,
              child: AnimatedBuilder(
                animation: motion,
                builder: (BuildContext context, Widget? child) {
                  return LiquidGlassDrop(
                    width: dropWidth,
                    height: dropHeight,
                    stretch: motion.stretch,
                    lift: motion.lift,
                    child: child!,
                  );
                },
                // 水滴下面画的是「当前指着的那个 tab」的内容，
                // 这样飞行途中玻璃里透出的图标也跟着换。
                child: _DropContent(
                  section: tabs[motion.index.clamp(0, tabs.length - 1)],
                  iconSize: iconSize,
                  labelHeight: labelHeight,
                  labelGap: labelGap,
                  lensSize: lensSize,
                ),              ),
            ),

            // ---- 标签组 ----
            Row(
              children: List<Widget>.generate(tabs.length, (i) {
                final section = tabs[i];
                final bool selected = section == active;
                return SizedBox(
                  width: itemWidth,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(section),
                    child: Column(
                      // 关键：min 让 Column 按内容高度收缩，不再占满父容器，
                      // 也就不会因为「居中对齐 + 内容超高」把文字挤出图标。
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          height: lensSize,
                          child: Center(
                            child: Icon(
                              selected ? section.selectedIcon : section.icon,
                              size: iconSize,
                              color: selected ? AppColors.pink : sub,
                            ),
                          ),
                        ),
                        if (!compact) ...<Widget>[
                          SizedBox(height: labelGap),
                          Text(
                            section.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.micro,
                              height: 1.1,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w500,
                              color: selected ? AppColors.pink : sub,
                            ),
                          ),
                        ],
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

/// 水滴玻璃底下透出的那一组「图标 + 文字」。
/// 放大由 [LiquidGlassDrop] 内部的 `Transform.scale` 负责，
/// 这里只管把内容按正常尺寸摆好。
///
/// 这一份内容是**玻璃里的折射像**，不是独立的可交互元素 ——
/// 真正的按钮在下面的标签行里。所以：
///
/// * 用 [ExcludeSemantics] 把它从无障碍树里摘掉，
///   否则读屏会把这个标签念两遍（标签行一次，玻璃里的像一次）；
/// * 用 [_DropContent.labelKey] 标记它，好让测试能精确定位
///   **标签行**里的那个同名 Text（两者文字相同，但职责不同）。
class _DropContent extends StatelessWidget {
  const _DropContent({
    required this.section,
    required this.iconSize,
    required this.labelHeight,
    required this.labelGap,
    required this.lensSize,
  });

  /// 玻璃里那一份标签的 key。
  ///
  /// 公开出来是为了让测试能区分「标签行里的标签」和「玻璃里的折射像」——
  /// 两者文字一模一样，但只有前者是可交互的。
  static const Key labelKey = Key('glass-drop-label');

  final AppSection section;
  final double iconSize;
  final double labelHeight;
  final double labelGap;
  final double lensSize;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Icon(
        section.selectedIcon,
        size: iconSize,
        color: AppColors.pink,
      ),
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
