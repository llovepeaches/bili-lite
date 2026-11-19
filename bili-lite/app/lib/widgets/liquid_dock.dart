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
import 'liquid_dock_reference.dart';
import 'squircle.dart';

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

  /// 标签行里那一份（真正可交互的）文字标签的 key。
  ///
  /// 底栏上每个 tab 的文字会出现两次：一次在标签行里（真正可交互的那个），
  /// 一次在水滴玻璃底下（折射像，只是视觉）。
  /// 测试要精确定位标签行里的那个时，用这个 key 排除折射像。
  /// 因为每个 tab 各有一个，所以按下标区分。
  static Key dropLabelKey(int index) => Key('glass-drop-label-$index');

  /// 胶囊本体的 key。
  ///
  /// 测试要验证「透镜顶出胶囊上沿」这类几何关系时，
  /// 需要一个**精确的胶囊矩形**做基准 —— 光晕的顶边不��拿来当代理
  /// （光晕比图标槽高，顶边天然高出胶囊 4.5pt）。
  static const Key capsuleKey = Key('glass-dock-capsule');

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
              // 玻璃关闭时的退化版也要用连续曲率圆角，
              // 否则「玻璃开关」一开一关，胶囊的轮廓会肉眼可见地变形。
              borderRadius: BorderRadius.circular(
                  GlassShape.capsuleRadius(capsuleHeight)),
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

  /// 单个 tab 的最小触控宽度（Apple HIG 的 44pt 下限）。
  static const double _minTabWidth = 44.0;

  /// 独立圆形按钮的最小边长。
  ///
  /// 窄屏时它会被压缩，但不低于 44 —— 否则就不好点了。
  static const double _minButtonSize = 44.0;

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
    // 参考实现的强调色：浅蓝 / 深蓝。dock 的选中态、拖动透镜与独立入口
    // 共用它，保证整条底栏是同一套材质语言。
    final Color accent = referenceDockAccent(dark);
    // 参考实现用 24dp 的折射高度；Flutter 这里只有倍率模型，
    // 在全局透镜倍率上再抬一档来表达同等强度，Web（lens==1）保持不折射。
    final double dockLens =
        config.lens > 1 ? math.min(1.20, config.lens + 0.10) : 1.0;

    final bool hasButton = widget.standalone.isNotEmpty;

    // ---------------------------------------------------------------
    // 窄屏保护：圆形按钮不能把标签组挤没
    // ---------------------------------------------------------------
    //
    // 双件式布局里，圆形按钮是**固定宽度**的（58），
    // 胶囊拿剩下的全部宽度。
    //
    // 在窄屏（比如 320pt）+ 多个 tab 的组合下，
    // 胶囊会被挤到每个 tab 只有二三十点宽 ——
    // 水滴玻璃珠撞在一起，标签也被挤没。
    //
    // 所以这里给标签组留一条**底线**：胶囊至少要能放下
    // 「每个 tab 一个 44pt 触控区」。不够的话先压缩圆形按钮
    // （它只有一个图标，压缩到 44 仍可用），
    // 真的还不够（tab 特别多）才让胶囊按实际宽度走 ——
    // 此时靠整格可点 + 文字省略号兜底。
    final int tabCount = widget.tabs.length;
    final double minCapsuleWidth =
        hasButton && tabCount > 0 ? tabCount * _GlassDock._minTabWidth : 0.0;

    double buttonSize = widget.buttonSize;
    double capsuleWidth = widget.width;
    if (hasButton) {
      capsuleWidth = math.max(0, widget.width - _GlassDock._gap - buttonSize);
      if (capsuleWidth < minCapsuleWidth) {
        // 先压按钮。
        final double available =
            widget.width - _GlassDock._gap - minCapsuleWidth;
        buttonSize = math.max(_GlassDock._minButtonSize, available);
        capsuleWidth = math.max(0, widget.width - _GlassDock._gap - buttonSize);
      }
    }

    // 画布坐标 = 底栏坐标 + _pad。
    final Rect capsuleRect = Rect.fromLTWH(
      _pad,
      _pad + (widget.rowHeight - widget.capsuleHeight) / 2,
      capsuleWidth,
      widget.capsuleHeight,
    );

    // 圆形玻璃：按压时按弹簧进度放大（Compose 的
    // `maxScale = (size.width + 16dp) / size.width`）。
    final double maxScale = (buttonSize + 16) / buttonSize;
    final double scale = 1 + (maxScale - 1) * progress;
    final double circleSize = buttonSize * scale;

    final Rect? circleRect = hasButton
        ? Rect.fromCenter(
            center: Offset(
              _pad + widget.width - buttonSize / 2,
              _pad + widget.rowHeight / 2,
            ),
            width: circleSize,
            height: circleSize,
          )
        : null;

    // 胶囊 + 圆形的并集：共享采样层只在这块形状内可见。
    //
    // 胶囊的两端用**连续曲率**圆角（iOS 的 continuous curvature），
    // 而不是正圆弧 —— 正圆弧在切点处曲率会从 0 突然跳到 1/r，
    // 那道折角就是「玻璃是贴上去的」的观感来源。
    final Path union = GlassShape.union(capsuleRect, circleRect);

    // ---- 胶囊的表面层与内容 ----
    final Widget capsuleFlow = clock == null
        ? const _FlowHighlight(phase: 0.18, intensity: 1)
        : ValueListenableBuilder<double>(
            valueListenable: clock,
            builder: (_, double v, __) =>
                _FlowHighlight(phase: v, intensity: 1),
          );

    final Widget capsuleSurface = _GlassSurface(
      shape: (Rect r) => GlassShape.capsule(r),
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

    // ---- 统一度量 ----
    //
    // 图标槽、光晕、透镜三者的尺寸全部从这里派生，
    // 避免「光晕按 A 算、透镜按 B 算」导致的对不齐。
    final _DockMetrics metrics = _DockMetrics(
      height: widget.capsuleHeight,
      itemWidth: widget.tabs.isEmpty ? 0 : capsuleWidth / widget.tabs.length,
      compact: widget.compact,
    );

    final Widget capsuleContent = _CapsuleContent(
      tabs: widget.tabs,
      active: widget.active,
      onSelect: widget.onSelect,
      height: widget.capsuleHeight,
      motion: _drop,
      compact: widget.compact,
      metrics: metrics,
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
        shape: (Rect r) => GlassShape.circle(r),
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
                    accent.withOpacity(dark ? 0.46 : 0.38),
                    accent.withOpacity(dark ? 0.24 : 0.18),
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
              // 图标随按钮尺寸缩放 —— 窄屏时按钮被压到 44，
              // 图标要跟着缩，否则会撑满整枚按钮。
              size: (buttonSize * 0.38).clamp(18.0, 22.0),
              color: selected ? accent : sub,
            ),
            // Liquid Glass v2 的暗边。
            Positioned.fill(
              child: GlassShapeEdge(
                shape: (Rect r) => GlassShape.circle(r),
                edgeColor: Colors.black.withOpacity(dark ? 0.30 : 0.10),
                edgeWidth: 1.4,
                innerShade: dark ? 0.24 : 0.06,
              ),
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
              if (circleRect != null)
                _ShadowBox(rect: circleRect, circle: true),

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
                      // 参考实现固定 8dp 模糊；不跟全局 navBlur 联动，
                      // 避免设置页调卡片强度时把系统 dock 的通透层次也改掉。
                      sigmaX: ReferenceDockStyle.blur,
                      sigmaY: ReferenceDockStyle.blur,
                    ),
                    child: Stack(
                      children: <Widget>[
                        // 每件玻璃在共享的模糊结果上再套一层自己的透镜。
                        Positioned.fromRect(
                          rect: capsuleRect,
                          child: ClipPath(
                            clipper: PathClipper(
                              GlassShape.capsule(capsuleRect),
                            ),
                            child: GlassSample(
                              // 模糊已经在共享层做过，这里只留透镜。
                              sigma: 0.01,
                              lens: dockLens,
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
                                lens: dockLens,
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
                key: LiquidGlassDock.capsuleKey,
                rect: capsuleRect,
                child: ClipPath(
                  clipper: PathClipper(GlassShape.capsule(capsuleRect)),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: capsuleSurface),
                      // 内壁顶部镜面亮线：让玻璃从内容上「浮」起来。
                      //
                      // 它画在表面层之上、暗边之下 —— 亮线是玻璃**内侧**的光，
                      // 不是浮在玻璃上面的贴纸。
                      Positioned.fill(
                        child: GlassTopHighlight(
                          shape: (Rect r) => GlassShape.capsule(r),
                          color: Colors.white.withOpacity(dark ? 0.30 : 0.72),
                          width: 1.6,
                        ),
                      ),
                      Positioned.fill(child: scrubbableCapsule),
                      // Liquid Glass v2 的暗边：压在最上面，把形状「勒」出来。
                      Positioned.fill(
                        child: GlassShapeEdge(
                          shape: (Rect r) => GlassShape.capsule(r),
                          edgeColor:
                              Colors.black.withOpacity(dark ? 0.30 : 0.10),
                          edgeWidth: 1.4,
                          innerShade: dark ? 0.24 : 0.06,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (circleRect != null && circleContent != null)
                Positioned.fromRect(
                  rect: circleRect,
                  child: ClipOval(child: circleContent),
                ),

              // 说明：AndroidLiquidGlass 参考实现没有「顶出胶囊上沿的
              // 抬起圆珠」。选中态是一枚**常驻、跟手、按压放大**的玻璃胶囊，
              // 已经画在胶囊内容层（_CapsuleContent）里；图标独立叠在其上。
              // 旧版的抬起圆珠层 _LensOverlay 已移除。
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
  // AndroidLiquidGlass 的 `containerColor`：
  // 浅色 #FAFAFA @ 40%，深色 #121212 @ 40%。
  //
  // `sampled` 保留在签名里是为了兼容旧调用；dock 现在跟参考实现一致，
  // 表面层本身只有 40% 不透明度，通透感来自共享 backdrop 的 8dp 模糊
  // 与 24dp 透镜，而不是靠加厚表面色。
  return referenceDockContainerGradient(dark);
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
    required this.shape,
    required this.gradient,
    required this.flow,
    this.hue,
    this.hueAlpha = 0,
    this.hueMix = 0,
  });

  /// 形状：与裁剪层、暗边层共用同一条路径。
  ///
  /// 上一版这里用 `BorderRadius.circular(1000)` 画渐变，
  /// 那是一个「半径远大于边长」的圆角矩形 ——
  /// 视觉上接近胶囊，但**与真正的连续曲率胶囊不是同一条曲线**，
  /// 于是 backdrop 采样区的边缘与表面层的边缘会有极细的错位，
  /// 亮边处能看到一条发虚的接缝。
  final Path Function(Rect rect) shape;
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
        // 渐变按**同一条路径**填充，与裁剪层严丝合缝。
        GlassShapeSurface(shape: shape, gradient: gradient),
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
      child: GlassShapeShadow(
        // 阴影必须跟着**同一条**路径走 ——
        // 用 BorderRadius 画的影子边缘是圆弧，
        // 跟连续曲率的胶囊轮廓错开一点点，
        // 在玻璃下方会露出一圈淡影。
        shape: (Rect r) =>
            circle ? GlassShape.circle(r) : GlassShape.capsule(r),
        shadows: <BoxShadow>[
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
    // 标签用**二级**色而不是三级 ——
    // 三级色（浅色 3.87:1）落在底栏的乳白玻璃上偏淡，
    // 而底栏是浮在内容之上的，需要比页面内的辅助文字更清楚。
    final sub = AppTextColor.secondary(context);
    if (tabs.isEmpty) return SizedBox(height: height);

    final int activeIndex = active == null ? -1 : tabs.indexOf(active!);

    return LayoutBuilder(builder: (context, constraints) {
      final double itemWidth = constraints.maxWidth / tabs.length;

      // 与 [_CapsuleContent] 用同一套度量 ——
      // 否则玻璃一开一关，底栏的图标大小和文字位置就会跳。
      final double labelBlock = _dockLabelHeight + _dockLabelGap;
      final double iconBox = _dockIconBox(
        height: height,
        itemWidth: itemWidth,
        withLabel: true,
      );
      final double iconSize = _dockIconSize(iconBox);
      final double stackHeight = iconBox + labelBlock;
      final double stackTop = (height - stackHeight) / 2;

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            if (activeIndex >= 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: activeIndex * itemWidth + (itemWidth - iconBox) / 2,
                top: stackTop,
                width: iconBox,
                height: iconBox,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(iconBox * 0.42),
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
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          top: stackTop,
                          left: 0,
                          right: 0,
                          height: iconBox,
                          child: Center(
                            child: Icon(
                              selected ? section.selectedIcon : section.icon,
                              size: iconSize,
                              color: selected ? AppColors.pink : sub,
                            ),
                          ),
                        ),
                        Positioned(
                          top: stackTop + iconBox + _dockLabelGap,
                          left: 0,
                          right: 0,
                          child: Text(
                            section.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppFontSize.micro,
                              height: 1.1,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w500,
                              color: selected ? AppColors.pink : sub,
                            ),
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

/// 标签行里文字的预留高度（字号 10.5、行高 1.1）。
///
/// 胶囊版（[_CapsuleContent]）与玻璃关闭时的退化版
/// （[_PlainCapsuleContent]）共用这一套度量，
/// 保证「玻璃开关」不会让底栏的排布跳变。
const double _dockLabelHeight = 12.0;

/// 图标与标签之间的间距。
///
/// iOS 26 的 tab bar 里，图标与标签之间只有约 2pt —— 标签几乎贴着图标。
/// 这里给 3pt，略宽一点点，让小字不至于糊在图标上。
const double _dockLabelGap = 3.0;

/// 玻璃珠内部的**折射放大倍率**。
///
/// 与 [LiquidGlassDrop] 里 `Transform.scale` 的取值保持一致 ——
/// 玻璃珠把底下的图标放大一点点，那是折射的观感来源。
///
/// 必须在这里参与尺寸预算：放大后的图标会比玻璃珠本身**溢出**约
/// `(倍率 - 1) / 2 × 珠高`，不预留的话图标会顶出胶囊。
const double _dockDropMagnification = 1.14;

/// 图标槽边长（正方形）—— 水滴玻璃珠、图标、标签都从它派生。
///
/// 上一版底栏里有**两套**互不相干的尺寸（`lensSize` 与 `dropHeight`），
/// 两者不一致时图标会偏离水滴中心、标签也会错位。
/// 现在统一成这一套度量。
///
/// 约束：
///
/// * 图标槽不能超过「胶囊高度 − 标签行」**除以折射放大倍率** ——
///   放大后的图标必须还在胶囊里；
/// * 也不能超过 tab 的可用宽度（否则相邻水滴会撞上）；
/// * 最小 26 —— 再小图标就糊了。
double _dockIconBox({
  required double height,
  required double itemWidth,
  required bool withLabel,
}) {
  final double labelBlock = withLabel ? _dockLabelHeight + _dockLabelGap : 0.0;
  // 竖向：放大后要装得下。
  final double byHeight = (height - labelBlock) / _dockDropMagnification;
  return math.max(
    26.0,
    math.min(
      math.min(itemWidth - 8.0, 44.0),
      // 玻璃珠不能把竖向空间吃满 ——
      // 珠子一大，图标与文字之间就被撑开一道空档，
      // 整组看起来是「散的」而不是「一个整体」。
      // 38 是 iOS tab bar 的观感值。
      math.min(byHeight, _dockMaxIconBox),
    ),
  );
}

/// 玻璃珠（图标槽）的最大边长。
///
/// 珠子一旦接近胶囊高度，图标与标签之间的视觉间隙就被撑开，
/// 整组标签会显得松散。38 是 iOS tab bar 的观感值。
const double _dockMaxIconBox = 38.0;

/// 整组标签的视觉上提量。
///
/// 10.5pt 的字在 1.1 行高里偏下，不补偿的话文字会贴住胶囊底边。
const double _dockVisualNudge = 1.5;

/// 图标尺寸：占图标槽的 62%，剩下 38% 是四周的呼吸空间。
///
/// iOS 的 tab bar 图标视觉尺寸约 22~24pt，
/// 而图标槽（玻璃珠罩住的范围）约 34~38pt。
double _dockIconSize(double iconBox) => (iconBox * 0.60).clamp(18.0, 24.0);

/// 底栏排布的**统一度量**。
///
/// 图标槽、标签行、柔边光晕、透镜四者都从这一套派生，
/// 避免「光晕按 A 算、透镜按 B 算」这种对不齐的经典问题。
class _DockMetrics {
  const _DockMetrics({
    required this.height,
    required this.itemWidth,
    required this.compact,
  });

  /// 胶囊高度。
  final double height;

  /// 单个 tab 的可用宽度。
  final double itemWidth;

  /// compact 模式：标签收起。
  final bool compact;

  /// 标签块高度（文字行高 + 图标与文字的间距）。
  double get labelBlock => compact ? 0.0 : _dockLabelHeight + _dockLabelGap;

  /// 图标槽边长（正方形）。
  double get iconBox => _dockIconBox(
        height: height,
        itemWidth: itemWidth,
        withLabel: !compact,
      );

  /// 图标尺寸。
  double get iconSize => _dockIconSize(iconBox);

  /// 「图标槽 + 标签行」整组相对胶囊顶部的偏移。
  double get stackTop =>
      (height - (iconBox + labelBlock)) / 2 - _dockVisualNudge;

  /// 柔边光晕（platter）的尺寸。
  ///
  /// 横向比图标槽宽 70% —— 参考图里那团光是「托着」图标与文字的，
  /// 比图标本身大一圈。
  double get glowWidth => iconBox * 1.70;

  /// 纵向：光晕要罩住**图标 + 文字**整组（参考图1 的光团下缘
  /// 已经压到标签上了），高度取整组高度。
  double get glowHeight => iconBox + labelBlock;

  /// 抬起态透镜的边长。
  ///
  /// 比图标槽大 35%：参考图里那枚透镜明显盖过了相邻的图标，
  /// 是一颗「浮在底栏之上」的玻璃珠，而不是图标旁边多了一块玻璃。
  double get lensSize => iconBox * _dockLensScale;
}

/// 抬起态透镜相对图标槽的放大倍数。
const double _dockLensScale = 1.35;

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
class _CapsuleContent extends StatefulWidget {
  const _CapsuleContent({
    required this.tabs,
    required this.active,
    required this.onSelect,
    required this.height,
    required this.motion,
    required this.compact,
    required this.metrics,
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

  /// 统一度量。
  final _DockMetrics metrics;

  @override
  State<_CapsuleContent> createState() => _CapsuleContentState();
}

/// 标签组的交互状态。
///
/// iOS 27 的按下反馈有两层：
///
/// 1. **图标回缩** —— 按下时图标微微缩小（不是变色），
///    松手用弹簧回弹。液态玻璃的手感主要来自这个回弹。
/// 2. **触点辉光** —— iOS 26 的原话是
///    *"a soft glow spreads from where the finger touched"*：
///    一团柔光从手指按下的位置扩散开。
///
/// 两者都由 [_GlassPress] 的弹簧驱动，
/// 所以贴在一起时能同相位地缩放与衰减。
class _CapsuleContentState extends State<_CapsuleContent>
    with SingleTickerProviderStateMixin {
  /// 按压弹簧（图标回缩 + 触点辉光共用一条曲线）。
  late final GlassPress _press = GlassPress(
    vsync: this,
    // 比圆形玻璃那枚更「脆」一点：ratio 0.55、stiffness 420，
    // 回弹快但不飘 —— 标签组是频繁点击的区域，太弹会显得廉价。
    dampingRatio: 0.55,
    stiffness: 420.0,
  );

  /// 当前被按下的 tab 索引；null 表示没有按压。
  int? _pressedIndex;

  /// 触点相对胶囊左上角的位置（辉光中心）。
  Offset? _touchPoint;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  /// 当前选中项在标签组里的下标。
  ///
  /// 找不到时回落到 0 —— 首帧时 `active` 可能还没定下来。
  int _activeIndex(List<AppSection> tabs) {
    final AppSection? active = widget.active;
    if (active == null) return 0;
    final int index = tabs.indexOf(active);
    return index < 0 ? 0 : index;
  }

  /// 手指按下。
  void _handleDown(int index, Offset local) {
    setState(() {
      _pressedIndex = index;
      _touchPoint = local;
    });
    _press.press();
  }

  /// 手指抬起 / 取消。
  void _handleUp() {
    if (_pressedIndex == null) return;
    setState(() {
      _pressedIndex = null;
      _touchPoint = null;
    });
    _press.release();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final motion = widget.motion;
    final height = widget.height;
    final compact = widget.compact;
    // 标签用**二级**色而不是三级 ——
    // 三级色（浅色 3.87:1）落在底栏的半透明玻璃上偏淡，
    // 而底栏是浮在内容之上的，需要比页面内的辅助文字更清楚。
    final sub = AppTextColor.secondary(context);
    final Color accent = referenceDockAccent(GlassPalette.of(context).dark);
    if (tabs.isEmpty) return SizedBox(height: height);

    return LayoutBuilder(builder: (context, constraints) {
      final double itemWidth = constraints.maxWidth / tabs.length;

      // ---------------------------------------------------------------
      // 一套度量，三个用途
      // ---------------------------------------------------------------
      //
      // 图标槽、柔边光晕、大透镜全部从 [widget.metrics] 派生，
      // 避免「光晕按 A 算、透镜按 B 算」这种对不齐。
      final _DockMetrics m = widget.metrics;
      final double iconBox = m.iconBox;
      final double iconSize = m.iconSize;
      final double stackTop = m.stackTop;

      // 把每个 tab 的中心 x 交给运动模型 —— 拖动擦洗要靠它算最近目标。
      //
      // 注意这里必须**在 build 里更新**：胶囊宽度会随屏幕宽度变化，
      // 缓存下来的中心坐标一旦过期，擦洗就会落到错误的 tab 上。
      final List<double> centers = List<double>.generate(
        tabs.length,
        (int i) => i * itemWidth + itemWidth / 2,
      );
      motion.setCenters(centers);

      // 首帧（以及胶囊宽度变化后）把水滴对齐到当前选中项。
      motion.ensureIndex(_activeIndex(tabs));

      // ---------------------------------------------------------------
      // 抬起态：玻璃珠的覆盖范围
      // ---------------------------------------------------------------
      //
      // 玻璃珠画在胶囊裁剪层**之外**，所以它会盖住底栏里的图标。
      // 珠子里那份放大像就是这个图标的「替身」，
      // 底栏里的原件必须让位 —— 否则两者叠在一起就是「双影」。
      //
      // 判定用**几何**而不是下标：珠子跟着手指走，
      // 未必正好压在某个 tab 的图标上；
      // 按几何算，谁被罩住谁让位，才不会漏。
      //
      // 注意：下面这些量必须在 [AnimatedBuilder] 的 builder 里**实时**算。
      // 它们依赖 `motion.lift` 和 `motion.x` ——
      // 而 `motion` 的变化只会重建 builder，不会重建外层 build，
      // 放在外层算出来的就是「静止态的快照」，
      // 抬起后判定结果完全不对（图标永远不让位，双影就是这么来的）。
      // 参考实现的选中胶囊**常驻**：静止时是一层淡蓝玻璃，
      // 按下 / 拖动时按 78/56 放大、随横向速度拉伸、带色散彩边。
      //
      // 它跟 `motion.x` 左右移动（擦洗跟手），进度由两条弹簧里较强的一条
      // 驱动：点击 tab 走 `_press`，拖动 / 切页飞行走 `motion.lift`。
      // 三者（位置、进度、速度）都在 builder 里实时读取 ——
      // 它们的变化只重建本 builder，不重建外层 build。
      final double pillWidth = math.max(44.0, itemWidth - 8);
      final double pillHeight = math.max(32.0, height - 8);

      return SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            // ---- 参考式常驻选中玻璃胶囊 ----
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                    <Listenable>[motion, _press.controller],
                  ),
                  builder: (BuildContext context, Widget? child) {
                    final double byTap = _pressedIndex == _activeIndex(tabs)
                        ? _press.progress.clamp(0.0, 1.0)
                        : 0.0;
                    final double byLift = motion.lift.clamp(0.0, 1.0);
                    final double pressed = math.max(byTap, byLift);
                    return Stack(
                      children: <Widget>[
                        Positioned(
                          left: motion.x - pillWidth / 2,
                          top: (height - pillHeight) / 2,
                          width: pillWidth,
                          height: pillHeight,
                          child: ReferenceSelectionPill(
                            progress: pressed,
                            velocity: motion.velocity,
                            accent: accent,
                            dark: GlassPalette.of(context).dark,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ---- 触点辉光 ----
            //
            // iOS 26 的 *"a soft glow spreads from where the finger touched"*：
            // 一团柔光从手指按下的位置扩散开。
            //
            // 它画在**内容之下**（图标之上、玻璃表面之下），
            // 所以光晕是从玻璃「里面」亮起来的，而不是浮在图标上面。
            if (_touchPoint != null)
              AnimatedBuilder(
                animation: _press.controller,
                builder: (BuildContext context, Widget? child) {
                  final double glow = (_press.progress).clamp(0.0, 1.0);
                  if (glow <= 0.01) return const SizedBox.shrink();
                  // `_touchPoint` 可能在 build 之后、动画回调之前
                  // 被 `_handleUp()` 置空（手指抬起后按压动画还在收尾），
                  // 所以这里必须空安全读取，不能用 `!`。
                  final Offset? center = _touchPoint;
                  if (center == null) return const SizedBox.shrink();
                  return _TouchGlow(
                    center: center,
                    progress: glow,
                  );
                },
              ),

            // ---- 标签组 ----
            //
            // 每个 tab 占满「胶囊宽度 ÷ tab 数」的一格，
            // 整格都是触控区（`HitTestBehavior.opaque`），
            // 高度是**整个胶囊高度**（62）——
            // 所以不管屏幕多窄、标签多密，
            // 可点区域的高度永远远大于 44pt 的下限。
            //
            // 横向宽度在极窄屏 + 多个 tab 时可能不足 44pt，
            // 那时靠相邻 tab 的无缝拼接保证「点哪儿都是某个 tab」，
            // 不留无法命中的死区。
            Row(
              children: List<Widget>.generate(tabs.length, (i) {
                final section = tabs[i];
                final bool selected = section == widget.active;
                // 参考实现里图标始终叠在玻璃胶囊之上、独立放大 ——
                // 不存在「抬起圆珠罩住图标、图标让位」这回事，
                // 所以这里不再有按 lift 淡出的 AnimatedBuilder。
                return SizedBox(
                  width: itemWidth,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails details) =>
                        _handleDown(i, details.localPosition),
                    onTapUp: (TapUpDetails details) => _handleUp(),
                    onTapCancel: () => _handleUp(),
                    onTap: () => widget.onSelect(section),
                    // 参考实现按下时整个 tab 内容放大到 1.2 倍，
                    // 松手回弹；选中玻璃胶囊同步按 78/56 放大。
                    child: AnimatedBuilder(
                      animation: _press.controller,
                      builder: (BuildContext context, Widget? child) {
                        final double pressed = _pressedIndex == i
                            ? _press.progress.clamp(0.0, 1.0)
                            : 0.0;
                        return Transform.scale(
                          scale: 1 + 0.20 * pressed,
                          child: child,
                        );
                      },
                      child: Stack(
                        children: <Widget>[
                          // 图标：垂直位置跟着上面的 stackTop 走，
                          // 保证图标正好落在水滴（透镜）中心。
                          Positioned(
                            top: stackTop,
                            left: 0,
                            right: 0,
                            height: iconBox,
                            child: Center(
                              child: Icon(
                                selected ? section.selectedIcon : section.icon,
                                size: iconSize,
                                color: selected ? accent : sub,
                              ),
                            ),
                          ),
                          // 文字标签：紧贴在图标槽下方。
                          if (!compact)
                            Positioned(
                              top: stackTop + iconBox + _dockLabelGap,
                              left: 0,
                              right: 0,
                              child: Text(
                                section.label,
                                key: LiquidGlassDock.dropLabelKey(i),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppFontSize.micro,
                                  height: 1.1,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: selected ? accent : sub,
                                ),
                              ),
                            ),
                        ],
                      ),
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

/// 触点柔光。
///
/// iOS 26 的 *"a soft glow spreads from where the finger touched"*：
/// 一团柔光从手指按下的位置扩散开，随松手淡出。
///
/// 实现上是一个**径向渐变**：中心亮、边缘完全透明，
/// 半径随按压进度略微扩张（扩散感），透明度随进度衰减。
///
/// 颜色取品牌粉的浅色调 —— 跟水滴玻璃珠的着色一致，
/// 辉光与玻璃看起来才像同一块材质在发光。
class _TouchGlow extends StatelessWidget {
  const _TouchGlow({
    required this.center,
    required this.progress,
  });

  /// 辉光中心（相对胶囊左上角）。
  final Offset center;

  /// 按压进度 0~1。
  final double progress;

  @override
  Widget build(BuildContext context) {
    // InteractiveHighlight 的光斑半径是容器短边的 1.5 倍；
    // 这里取一个与之同量级的扩散半径，并用加色白光叠加。
    final double radius = 26.0 + ReferenceDockStyle.blur * 3.25 * progress;
    return IgnorePointer(
      child: CustomPaint(
        painter: _TouchGlowPainter(
          center: center,
          radius: radius,
          opacity: 0.23 * progress,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TouchGlowPainter extends CustomPainter {
  const _TouchGlowPainter({
    required this.center,
    required this.radius,
    required this.opacity,
  });

  final Offset center;
  final double radius;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.001) return;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            Colors.white.withOpacity(opacity),
            Colors.white.withOpacity(opacity * 0.42),
            Colors.white.withOpacity(0),
          ],
          <double>[0.0, 0.45, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(covariant _TouchGlowPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radius != radius ||
      oldDelegate.opacity != opacity;
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

/// 玻璃内壁的**顶部镜面亮线**。
///
/// 这是让玻璃「浮」起来的关键细节。
///
/// 物理上：一块有厚度的玻璃，上边缘的内侧会形成一条**全反射亮线**
/// （像光纤的包层）。iOS 的 Liquid Glass 把它做成了可见的一像素高光，
/// 沿着形状的**内壁**走 —— 所以它不是一条横贯的直线，
/// 而是贴着轮廓走的：两端随圆角收进去，中间一段平直。
///
/// 实现上不能直接描边整条路径（那会在底部也出现一条亮线），
/// 所以这里只取路径的**上半段**来描。
///
/// 取上半段的方法：把路径按 y 方向切成两半，
/// 只保留上边界那一部分 —— 具体做法是先用整条路径做描边，
/// 再用一条「只保留顶部」的裁剪矩形切掉下半部分。
class GlassTopHighlight extends StatelessWidget {
  const GlassTopHighlight({
    Key? key,
    required this.shape,
    required this.color,
    this.width = 1.6,
    this.inset = 1.2,
  }) : super(key: key);

  final Path Function(Rect rect) shape;

  /// 亮线颜色。
  final Color color;

  /// 亮线宽度。
  final double width;

  /// 从轮廓向内缩进多少（亮线贴着内壁，不是压在轮廓上）。
  final double inset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GlassTopHighlightPainter(
          shape: shape,
          color: color,
          width: width,
          inset: inset,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GlassTopHighlightPainter extends CustomPainter {
  const _GlassTopHighlightPainter({
    required this.shape,
    required this.color,
    required this.width,
    required this.inset,
  });

  final Path Function(Rect rect) shape;
  final Color color;
  final double width;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.alpha == 0) return;
    final Rect rect = Offset.zero & size;
    final Path path = shape(rect);

    // 只保留上半段：用一个随高度收缩的矩形做裁剪。
    //
    // 裁剪区域的高度取形状高度的 42% ——
    // 略大于一半，保证两侧圆角里的亮线也能被切出来，
    // 但不会漫到底边去。
    final double band = size.height * 0.42;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, band));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
    canvas.restore();

    // 内壁的第二层：更淡更粗的一层，制造「光晕」。
    if (inset > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, band));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3.4
          ..color = color.withOpacity(color.opacity * 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GlassTopHighlightPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.inset != inset;
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
