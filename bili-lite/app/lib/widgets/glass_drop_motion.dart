import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// iOS 26/27 液态玻璃底栏的「水滴透镜」运动模型。
///
/// 这套模型照着 iOS 的真实行为搭，拆成四个阶段：
///
/// 1. **抬起（lift）**：按下的一刻，水滴从底栏的「底盘」上**离开** ——
///    变大的同时底盘淡出，于是它从「一块贴在栏上的玻璃」变成
///    「一颗悬着的透明水滴」。iOS 27 的原话是
///    *"it grows, its platter fades so it becomes clear glass"*。
/// 2. **飞行（travel）**：水滴朝目标 tab 走，走的是**弹簧**而不是缓动曲线。
///    飞行途中按剩余距离**拉伸**（squash & stretch）——
///    离得越远拉得越开，临近落位时压扁。
/// 3. **落位（land）**：到位后回到静止形状，弹簧的过冲自带一点回弹。
/// 4. **擦洗（scrub）**：手指按住沿底栏拖动时，水滴**跟手**移动，
///    松手才落到最近的那个 tab 上。
///
/// 关键的一点：**玻璃下的内容会跟着放大**。iOS 里被水滴盖住的那个
/// 图标和文字，在玻璃底下渲染得比平时大 —— 放大是折射效果，
/// 不是「选中态变大了」。
class GlassDropMotion extends ChangeNotifier {
  GlassDropMotion({required TickerProvider vsync})
      : _lift = AnimationController.unbounded(vsync: vsync),
        _travel = AnimationController.unbounded(vsync: vsync) {
    _lift.addListener(notifyListeners);
    _travel.addListener(notifyListeners);
  }

  /// 抬起/落位的控制器：0 = 贴在底盘上，1 = 完全抬起。
  final AnimationController _lift;

  /// 飞行进度：0 = 出发，1 = 到位。
  final AnimationController _travel;

  /// 底栏里各个 tab 的中心 x 坐标（局部坐标）。
  List<double> _centers = const <double>[];

  /// 当前水滴所指的 tab 下标。
  int _index = 0;

  /// 拖动擦洗时的目标 x（null 表示没在擦洗）。
  double? _scrubX;

  /// 飞行的起点下标（落位后仍然保留，用于算拉伸幅度）。
  int _travelOrigin = 0;

  /// 飞行的起点 x（null 表示用 `_centers[_travelOrigin]`）。
  ///
  /// 擦洗松手时需要这个：手指是在**两个 tab 之间**松手的，
  /// 水滴应该从手指松开的地方继续飞到落点，
  /// 而不是先跳回上一个 tab 的中心再飞过去。
  double? _travelOriginX;

  /// 抬起进度（0..1，弹簧可以过冲）。
  double get lift => _lift.value;

  /// 飞行进度（0..1，弹簧可以过冲）。
  double get travel => _travel.value;

  // ---- 测试钩子 ----
  //
  // 动画进度由弹簧驱动，测试里没法精确停在某一帧。
  // 这两个 setter 把进度直接写进控制器，
  // 让断言能落在「飞行中段」「完全抬起」这些确定的时刻上。
  //
  // 只在测试里用 —— 名字带 ForTest 是为了在代码评审时一眼看出用途。

  /// 把飞行进度直接设为 [value]（0..1）。
  void setTravelForTest(double value) {
    _travel.value = value;
  }

  /// 把抬起进度直接设为 [value]（0..1）。
  void setLiftForTest(double value) {
    _lift.value = value;
  }

  /// 当前指向的 tab 下标。
  int get index => _index;

  /// 是否正在被手指擦洗。
  bool get scrubbing => _scrubX != null;

  /// 水滴当前的中心 x。
  double get x {
    if (_scrubX != null) return _scrubX!;
    if (_centers.isEmpty) return 0;
    final int from = _travelOrigin;
    final int to = _index;
    if (from == to && _travelOriginX == null) return _centers[to];
    // 飞行途中：在起点与终点之间插值，但用**弹性缓动**而不是线性 ——
    // 线性会让水滴看起来像在滑轨上，而不是被甩过去。
    final double t = _easeTravel(_travel.value);
    final double start = _travelOriginX ?? _centers[from];
    return start + (_centers[to] - start) * t;
  }

  /// 飞行途中的形状拉伸系数。
  ///
  /// > 1 表示被拉长（纵向变高、横向变窄），< 1 表示被压扁。
  /// 规律：离目标越远拉得越开，临近落位时压扁。
  double get stretch {
    if (_travelOrigin == _index && _travelOriginX == null) return 1;
    final double t = _travel.value;
    if (t <= 0 || t >= 1) return 1;
    // 飞行中：用一个 0→1→0 的包络，中段最拉。
    final double envelope = math.sin(math.min(t, 1) * math.pi);
    final double start = _travelOriginX ?? _centers[_travelOrigin];
    final double distance = (_centers[_index] - start).abs();
    final double amount = (distance / 120).clamp(0.0, 1.0);
    return 1 + envelope * amount * 0.42;
  }

  /// 飞行途中的弹性缓动。
  ///
  /// 起步略慢、中段最快、末尾减速 —— 比 `easeOutCubic` 更「甩」。
  double _easeTravel(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return t < 0.5
        ? 4 * t * t * t
        : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  /// 更新各个 tab 的中心 x。
  void setCenters(List<double> centers) => _centers = centers;

  /// 立即落到某个 tab（无动画）。
  void jumpTo(int index) {
    _index = index.clamp(0, math.max(0, _centers.length - 1));
    _travelOrigin = _index;
    _travelOriginX = null;
    _scrubX = null;
    _lift.value = 0;
    _travel.value = 1;
  }

  /// 飞向某个 tab。
  void travelTo(int index) {
    if (_centers.isEmpty) return;
    final int clamped = index.clamp(0, _centers.length - 1);
    if (clamped == _index && _travel.value >= 1 && !_scrubbing) return;
    _travelOrigin = _index;
    _index = clamped;
    _scrubX = null;
    _travelOriginX = null;

    // 抬起：底盘淡出、水滴变通透。
    _lift.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 26),
        _lift.value,
        1,
        0,
      ),
    );

    _animateTravel();
  }

  /// 飞行的弹簧动画（iOS 的 travel spring —— 略微过冲，落位后自然回弹）。
  ///
  /// 进度从 **0** 开始 —— `_travel.value` 是「从出发点到落点的归一化进度」，
  /// 而出发点已经记在 `_travelOrigin` / `_travelOriginX` 里了。
  /// 若从 `_travel.value` 起跳，第二次切换时弹簧就是 1 → 1，水滴根本不动。
  void _animateTravel() {
    _travel.value = 0;
    _travel.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 340, damping: 30),
        0,
        1,
        0,
      ),
    );
  }

  /// 按下：抬起但先不飞（iOS 里「按住不放」时水滴是悬着的）。
  void pressLift() {
    _lift.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 26),
        _lift.value,
        1,
        0,
      ),
    );
  }

  /// 手指沿底栏拖动：水滴跟手。
  bool scrubTo(double localX) {
    if (_centers.isEmpty) return false;
    // 水滴不能被拖出底栏 —— iOS 里透镜始终待在栏内，
    // 拖到头就停在最后一个 tab 上。这里按首尾 tab 的中心做钳制。
    _scrubX = localX.clamp(_centers.first, _centers.last);
    _lift.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 520, damping: 30),
        _lift.value,
        1,
        0,
      ),
    );
    return true;
  }

  /// 松手：落到最近的那个 tab。
  void scrubRelease() {
    if (_centers.isEmpty) return;
    // 先记下手指松开时的位置，再清掉擦洗状态 ——
    // 否则 `x` 会突然跳回上一个 tab 的中心，水滴「瞬移」一下再飞过去。
    final double releaseX = x;
    _scrubX = null;
    final int nearest = _nearestIndex(releaseX);
    _index = nearest;
    _travelOrigin = nearest;
    // 起点是手指松开的地方，不是那个 tab 的中心。
    _travelOriginX = releaseX;
    _animateTravel();
  }

  /// 找出离给定 x 最近的 tab 下标。
  int _nearestIndex(double localX) {
    int best = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < _centers.length; i++) {
      final double d = (_centers[i] - localX).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// 水滴下面那个 tab 的放大系数。
  ///
  /// iOS 里被玻璃盖住的图标和文字渲染得**更大** —— 放大来自折射，
  /// 不是选中态。所以这一项只取决于「水滴是否盖在上面」。
  double get underGlassScale => 1 + 0.14 * lift.clamp(0.0, 1.0);

  bool get _scrubbing => _scrubX != null;

  @override
  void dispose() {
    _lift.removeListener(notifyListeners);
    _travel.removeListener(notifyListeners);
    _lift.dispose();
    _travel.dispose();
    super.dispose();
  }
}
