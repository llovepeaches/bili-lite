import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/nav_section.dart';
import '../core/theme.dart';
import '../core/tokens.dart';

/// 扁平底部导航。
///
/// 这一版彻底移除了液态玻璃：没有 `BackdropFilter`、没有透镜折射、
/// 没有镜面高光、没有色散、没有触点辉光，也没有半透明层叠。
/// 底栏是一整条不透光的主题背景，选中项是浅粉圆角实底，
/// 图标与文字统一使用主题主文字色。
///
/// 保留 [LiquidGlassDock] 的类名和构造参数，是为了不改动导航壳、
/// 路由和调用点；「交互功能不变」体现在：
/// * 标签组点按仍回调 [onSelect]；
/// * 独立入口（搜索）仍固定在右侧、不参与标签排序；
/// * 按住标签组横向拖动仍可擦洗选择，松手落位；
/// * compact 模式仍收起文字、降低底栏高度。
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

  final List<AppSection> tabs;
  final List<AppSection> standalone;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;

  /// 标签组高度（compact 时按比例压矮）。
  final double capsuleHeight;

  /// 右侧独立入口的格宽。
  final double buttonSize;

  /// 滚动收起模式：只留图标。
  final bool compact;

  /// 标签文字的 key。保留旧名称，避免测试与调用点改名。
  static Key dropLabelKey(int index) => Key('glass-drop-label-$index');

  /// 底栏主体的 key。保留旧名称，避免测试与调用点改名。
  static const Key capsuleKey = Key('glass-dock-capsule');

  /// 选中项的 key，供视觉回归测试定位。
  static const Key selectionKey = Key('flat-dock-selection');

  /// 单个条目内容区的 key，供按压反馈测试定位。
  static Key itemContentKey(int index) => Key('flat-dock-item-$index');

  @override
  Widget build(BuildContext context) {
    final double rowHeight = compact ? capsuleHeight * 0.76 : capsuleHeight;
    final List<AppSection> items = <AppSection>[...tabs, ...standalone];

    return SizedBox(
      height: rowHeight + 12,
      child: DecoratedBox(
        decoration:
            BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
        child: _FlatDock(
          key: capsuleKey,
          items: items,
          tabCount: tabs.length,
          active: active,
          onSelect: onSelect,
          rowHeight: rowHeight,
          standaloneSlot: buttonSize,
          compact: compact,
        ),
      ),
    );
  }
}

class _FlatDock extends StatefulWidget {
  const _FlatDock({
    Key? key,
    required this.items,
    required this.tabCount,
    required this.active,
    required this.onSelect,
    required this.rowHeight,
    required this.standaloneSlot,
    required this.compact,
  }) : super(key: key);

  final List<AppSection> items;
  final int tabCount;
  final AppSection? active;
  final ValueChanged<AppSection> onSelect;
  final double rowHeight;
  final double standaloneSlot;
  final bool compact;

  @override
  State<_FlatDock> createState() => _FlatDockState();
}

class _FlatDockState extends State<_FlatDock> {
  /// 擦洗时选中块的临时中心 x（相对标签组左边界）。
  final ValueNotifier<double> _scrubX = ValueNotifier<double>(0);

  /// 按下时的指针 x。
  double _pointerStartX = 0;

  /// 按下时选中块的中心 x。
  double _scrubBaseX = 0;

  /// 是否已越过擦洗阈值。
  bool _scrubbing = false;

  /// 擦洗落点（标签组下标）。
  int _scrubIndex = 0;

  /// 当前按下的条目（整条底栏统一下标）。
  int? _pressedItem;

  /// 首帧直接把选中块放到位，避免从左上角滑入。
  bool _initialized = false;

  @override
  void dispose() {
    _scrubX.dispose();
    super.dispose();
  }

  int get _standaloneCount => widget.items.length - widget.tabCount;

  int get _selectionIndex {
    if (widget.active == null) return 0;
    final int index = widget.items.indexOf(widget.active!);
    return index < 0 ? 0 : index;
  }

  double _centerOf(int index, double tabsWidth, double tabSlot,
      double standaloneWidth, double standaloneSlotWidth) {
    if (tabCountIsEmpty) {
      return tabsWidth + (index + 0.5) * standaloneSlotWidth;
    }
    if (index < widget.tabCount) return (index + 0.5) * tabSlot;
    final int standaloneIndex = index - widget.tabCount;
    return tabsWidth + (standaloneIndex + 0.5) * standaloneSlotWidth;
  }

  bool get tabCountIsEmpty => widget.tabCount == 0;

  void _handlePointerDown(PointerDownEvent event, double tabsWidth) {
    if (widget.tabCount < 2 || event.localPosition.dx > tabsWidth) return;
    _pointerStartX = event.localPosition.dx;
    _scrubBaseX = _scrubX.value;
    _scrubbing = false;
    _scrubIndex = _selectionIndex;
  }

  void _handlePointerMove(
      PointerMoveEvent event,
      double tabsWidth,
      double tabSlot,
      int selectionIndex,
      double standaloneWidth,
      double standaloneSlotWidth) {
    if (widget.tabCount < 2 || event.localPosition.dx > tabsWidth) return;
    final double delta = event.localPosition.dx - _pointerStartX;
    if (!_scrubbing) {
      if (delta.abs() < 6) return;
      _scrubbing = true;
      _scrubBaseX = _centerOf(
        selectionIndex,
        tabsWidth,
        tabSlot,
        standaloneWidth,
        standaloneSlotWidth,
      );
    }
    final double next = (_scrubBaseX + delta).clamp(0.0, tabsWidth);
    _scrubX.value = next;
    _scrubIndex =
        math.min(widget.tabCount - 1, math.max(0, (next / tabSlot).round()));
  }

  void _handlePointerUp() {
    if (!_scrubbing) return;
    _scrubbing = false;
    if (_scrubIndex >= 0 && _scrubIndex < widget.tabCount) {
      widget.onSelect(_tabsSafe[_scrubIndex]);
    }
  }

  List<AppSection> get _tabsSafe =>
      widget.items.take(widget.tabCount).toList(growable: false);

  void _setPressed(int index, bool pressed) {
    if (pressed) {
      if (_pressedItem == index) return;
      setState(() => _pressedItem = index);
    } else {
      if (_pressedItem != index) return;
      setState(() => _pressedItem = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints size) {
      final double width = size.maxWidth;
      final int standaloneCount = _standaloneCount;
      final double standaloneWidth =
          standaloneCount == 0 ? 0.0 : widget.standaloneSlot * standaloneCount;
      final double tabsWidth = math.max(0.0, width - standaloneWidth);
      final double tabSlot =
          widget.tabCount == 0 ? 0.0 : tabsWidth / widget.tabCount;
      final double standaloneSlotWidth =
          standaloneCount == 0 ? 0.0 : standaloneWidth / standaloneCount;
      final int selectionIndex = _selectionIndex;

      // 首次布局 / 尺寸变化后，把擦洗位置同步到当前选中项。
      if (!_scrubbing) {
        final double center = _centerOf(
          selectionIndex,
          tabsWidth,
          tabSlot,
          standaloneWidth,
          standaloneSlotWidth,
        );
        if (_scrubX.value != center) _scrubX.value = center;
      }
      final Duration selectionDuration =
          _initialized ? const Duration(milliseconds: 240) : Duration.zero;
      _initialized = true;

      return ValueListenableBuilder<double>(
        valueListenable: _scrubX,
        builder: (BuildContext context, double scrubX, Widget? _) {
          final bool showScrub = _scrubbing &&
              widget.tabCount > 1 &&
              selectionIndex < widget.tabCount;
          final double center = showScrub
              ? scrubX.clamp(0.0, tabsWidth)
              : _centerOf(
                  selectionIndex,
                  tabsWidth,
                  tabSlot,
                  standaloneWidth,
                  standaloneSlotWidth,
                );
          final double slotWidth =
              selectionIndex < widget.tabCount ? tabSlot : standaloneSlotWidth;
          final double selectionWidth =
              math.max(34.0, math.min(64.0, slotWidth - 10));
          final double selectionHeight = widget.compact ? 40 : 50;
          final double selectionTop = (widget.rowHeight - selectionHeight) / 2;

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent e) =>
                _handlePointerDown(e, tabsWidth),
            onPointerMove: (PointerMoveEvent e) => _handlePointerMove(
              e,
              tabsWidth,
              tabSlot,
              selectionIndex,
              standaloneWidth,
              standaloneSlotWidth,
            ),
            onPointerUp: (PointerUpEvent _) => _handlePointerUp(),
            onPointerCancel: (PointerCancelEvent _) => _handlePointerUp(),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                AnimatedPositioned(
                  duration: selectionDuration,
                  curve: Curves.easeOutCubic,
                  left: center - selectionWidth / 2,
                  top: selectionTop,
                  width: selectionWidth,
                  height: selectionHeight,
                  child: const DockSelectionBlock(
                      key: LiquidGlassDock.selectionKey),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: tabsWidth,
                        height: widget.rowHeight,
                        child: Row(
                          children:
                              List<Widget>.generate(widget.tabCount, (int i) {
                            final AppSection section = widget.items[i];
                            return _DockItem(
                              index: i,
                              section: section,
                              selected: section == widget.active,
                              compact: widget.compact,
                              pressed: _pressedItem == i,
                              onSelect: widget.onSelect,
                              onPressedChanged: (bool value) =>
                                  _setPressed(i, value),
                            );
                          }),
                        ),
                      ),
                      if (standaloneCount > 0)
                        SizedBox(
                          width: standaloneWidth,
                          height: widget.rowHeight,
                          child: Row(
                            children:
                                List<Widget>.generate(standaloneCount, (int i) {
                              final int index = widget.tabCount + i;
                              final AppSection section = widget.items[index];
                              return _DockItem(
                                index: index,
                                section: section,
                                selected: section == widget.active,
                                compact: widget.compact,
                                pressed: _pressedItem == index,
                                onSelect: widget.onSelect,
                                onPressedChanged: (bool value) =>
                                    _setPressed(index, value),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

/// 扁平选中块：浅粉圆角实底，无边框、无发光、无阴影。
class DockSelectionBlock extends StatelessWidget {
  const DockSelectionBlock({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color color =
        context.isDark ? const Color(0xFF50313B) : AppColors.pinkSoft;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.index,
    required this.section,
    required this.selected,
    required this.compact,
    required this.pressed,
    required this.onSelect,
    required this.onPressedChanged,
  });

  final int index;
  final AppSection section;
  final bool selected;
  final bool compact;
  final bool pressed;
  final ValueChanged<AppSection> onSelect;
  final ValueChanged<bool> onPressedChanged;

  @override
  Widget build(BuildContext context) {
    final Color color = context.primaryTextColor;
    final bool isStandalone = section.standalone;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPressedChanged(true),
        onTapUp: (_) => onPressedChanged(false),
        onTapCancel: () => onPressedChanged(false),
        onTap: () => onSelect(section),
        child: AnimatedScale(
          scale: pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: SizedBox(
            key: LiquidGlassDock.itemContentKey(index),
            child: isStandalone
                ? Center(
                    child: Icon(
                      selected ? section.selectedIcon : section.icon,
                      size: 22,
                      color: color,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        selected ? section.selectedIcon : section.icon,
                        size: 22,
                        color: color,
                      ),
                      if (!compact) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          section.label,
                          key: LiquidGlassDock.dropLabelKey(index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            height: 1.15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
