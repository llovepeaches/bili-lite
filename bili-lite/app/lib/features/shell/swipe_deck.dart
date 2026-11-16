import 'package:flutter/material.dart';

/// 可左右拖动的分页容器：手指按住内容区拖动时，页面**跟手平移**，
/// 松手后按位移 / 速度吸附到目标页。
///
/// 与常见的 `PageView` 相比，这里刻意不用 `PageView`：
/// 1. `PageView` 离开视口的子树会被销毁，首页的滚动位置、搜索页已输入的
///    关键词都会丢。这里页面始终挂载在树里（`Offstage` 只停绘制），
///    状态全部保活；
/// 2. `PageView` 会把水平拖拽手势整个吃掉，页面内部横向滚动的小控件
///    （首页的分区横条）就滑不动了。这里手势挂在内容区最外层，
///    内层控件在命中测试路径里优先拿到手势，因此分区横条仍能正常横滑；
/// 3. 底栏完全不在这个容器里 —— 滑动时只有内容区动，底栏固定不动，
///    仅通过选中项高光的变化指示当前页面。
///
/// 索引采用**受控模式**：[index] 是外部认定的当前页；本组件内部拖动
/// 完成后通过 [onIndexChanged] 上报，外部更新 [index] 后本组件再动画过去。
/// 拖动过程中用 [onIndexPreview] 实时上报「最接近的页」，让底栏高光跟手移动，
/// 但不会改变 [index]。
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    Key? key,
    required this.pages,
    required this.index,
    required this.onIndexChanged,
    this.onIndexPreview,
  }) : super(key: key);

  /// 页面列表，顺序即导航顺序。
  final List<Widget> pages;

  /// 外部认定的当前页下标。
  final int index;

  /// 吸附到某一页之后回调（此时选中项高光才最终确定）。
  final ValueChanged<int> onIndexChanged;

  /// 拖动过程中实时回调「最接近的页面」，让底栏高光跟手移动。
  ///
  /// 拖动被回弹时同样会回调原页，把高光拉回去。
  final ValueChanged<int>? onIndexPreview;

  @override
  SwipeDeckState createState() => SwipeDeckState();
}

class SwipeDeckState extends State<SwipeDeck>
    with SingleTickerProviderStateMixin {
  /// 拖过这个比例就吸附到邻页。取 0.28 而不是 0.5：手指不用滑过半屏
  /// 才切页，手感更接近 iOS 的分页控件。
  static const double _commitThreshold = 0.28;

  /// 连续位移 → 页方向：正数是下一页，负数是上一页。
  int _directionOf(double fraction) {
    if (fraction > _commitThreshold) return 1;
    if (fraction < -_commitThreshold) return -1;
    return 0;
  }

  /// 当前已经提交（吸附完成）的页序号。
  int _index = 0;

  /// 相对 [_index] 的连续偏移，-1 ~ 1。0 表示正停在 [_index] 上。
  double _fraction = 0;

  /// 拖动累计位移（像素）。
  double _dragAccum = 0;

  double _width = 0;

  /// 最近一次「已提交」并上报过的页序号，用于去重。
  int _committed = 0;

  /// 最近一次上报过的预览页序号，用于去重。
  int _previewed = 0;

  late final AnimationController _anim;
  Animation<double>? _animValue;

  @override
  void initState() {
    super.initState();
    _index = widget.index.clamp(0, _maxIndex);
    _committed = _index;
    _previewed = _index;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        final value = _animValue?.value ?? 0;
        if (value != _fraction) setState(() => _fraction = value);
      });
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了当前页（底栏点击 / 返回键回首页）：把内容区滑过去。
    if (widget.index != oldWidget.index && widget.index != _index) {
      goTo(widget.index);
    }
  }

  int get _maxIndex => widget.pages.isEmpty ? 0 : widget.pages.length - 1;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 跳到指定页。跨多页时逐格滑动，动画连贯。
  Future<void> goTo(int target) async {
    final clamped = target.clamp(0, _maxIndex);
    while (_index != clamped) {
      final dir = clamped > _index ? 1 : -1;
      await _slide(dir);
    }
  }

  /// 播完一格滑动并提交。
  Future<void> _slide(int dir) async {
    _anim.stop();
    _animValue = Tween<double>(begin: _fraction, end: dir.toDouble()).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    await _anim.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _index = (_index + dir).clamp(0, _maxIndex);
      _fraction = 0;
    });
    _emit(_index);
  }

  /// 上报「已提交」的页序号。
  ///
  /// 与预览分开计数：拖动过程中预览值可能已经等于目标页，
  /// 但只有真正吸附完成才算提交。
  void _emit(int index) {
    if (_committed == index) return;
    _committed = index;
    widget.onIndexChanged(index);
  }

  void _handleDragStart(DragStartDetails details) {
    _anim.stop();
    _dragAccum = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_width <= 0) return;
    _dragAccum += details.delta.dx;
    // 向左拖（dx 为负）时下一页从右侧进来，因此 fraction 取负号：
    // fraction = +0.5 表示已经往「下一页」方向走了一半。
    final next = (-_dragAccum / _width).clamp(-1.0, 1.0);
    if (next != _fraction) setState(() => _fraction = next);

    // 预览与提交用同一个阈值：拖过 [_commitThreshold] 就认为会切到邻页，
    // 高光先一步挪过去，松手回弹时再挪回来。两者不一致会出现
    // 「高光在第二页、页面还在第一页」的错位。
    final nearest = (_index + _directionOf(next)).clamp(0, _maxIndex);
    if (nearest != _previewed) {
      _previewed = nearest;
      widget.onIndexPreview?.call(nearest);
    }
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;
    double dir = 0;
    if (velocity.abs() > 420) {
      // 速度优先：左滑（负速度）去下一页，右滑回上一页。
      dir = velocity < 0 ? 1 : -1;
    } else if (_fraction.abs() > _commitThreshold) {
      dir = _directionOf(_fraction).toDouble();
    }

    final target = _index + dir;
    if (dir == 0 || target < 0 || target > _maxIndex) {
      await _animateTo(0);
      // 回弹：高光退回原页。
      if (_previewed != _index) {
        _previewed = _index;
        widget.onIndexPreview?.call(_index);
      }
      return;
    }

    await _slide(dir.toInt());
  }

  Future<void> _animateTo(double target) async {
    _anim.stop();
    _animValue = Tween<double>(begin: _fraction, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
    await _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          // deferToChild：命中测试交给子页面，内层控件（首页分区横条、
          // Slider）先拿到手势；外层识别器只在子页面被命中时才入竞技场，
          // 因此竖向滚动列表的竖向识别器会先出局，横向手势落到本层。
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: _handleDragStart,
          onHorizontalDragUpdate: _handleDragUpdate,
          onHorizontalDragEnd: _handleDragEnd,
          child: Stack(
            children: <Widget>[
              for (int i = 0; i < widget.pages.length; i++)
                Positioned.fill(
                  // 只保留当前页与相邻页参与绘制，其余页面仅挂载不绘制，
                  // 这样既保住状态，又不会一次渲染四屏内容。
                  child: Offstage(
                    offstage: (i - _index).abs() > 1,
                    child: Transform.translate(
                      offset: Offset((i - _index - _fraction) * _width, 0),
                      child: widget.pages[i],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
