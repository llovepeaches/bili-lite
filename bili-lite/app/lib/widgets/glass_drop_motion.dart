import 'dart:async';
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
        _travel = AnimationController.unbounded(vsync: vsync),
        _velocity = AnimationController.unbounded(vsync: vsync) {
    _lift.addListener(notifyListeners);
    _travel.addListener(notifyListeners);
    // 横向速度：拖动时跟手计算，松手后弹回 0。
    // 参考 DampedDragAnimation 用 VelocityTracker 算速度来驱动胶囊形变。
    _velocity.addListener(notifyListeners);
    _travel.addStatusListener(_handleTravelStatus);
  }

  /// 横向速度控制器：值域 -1~1（归一化到「每秒跨几个 tab」的量级），
  /// 拖动中被 snap 到当前瞬时速度，松手后用弹簧衰减回 0。
  final AnimationController _velocity;

  /// 抬起/落位的控制器：0 = 贴在底盘上，1 = 完全抬起。
  final AnimationController _lift;

  /// 飞行进度：0 = 出发，1 = 到位。
  final AnimationController _travel;

  /// 底栏里各个 tab 的中心 x 坐标（局部坐标）。
  List<double> _centers = const <double>[];

  /// 当前水滴所指的 tab 下标。
  int _index = 0;

  /// 飞行落位后把透镜收回去。
  ///
  /// 抬起态（大透镜 + 色散）只在**交互中**存在：
  /// 按住拖动、或切换 tab 的飞行途中。
  /// 落位之后透镜必须收起，让位给静止态的柔边光晕 ——
  /// 否则底栏会长期停在一颗悬空的玻璃珠上。
  void _handleTravelStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _traveling = false;
    // 擦洗中不收起：手指还按着，透镜应当继续悬着。
    if (_scrubX != null) return;
    Timer.run(() {
      _springLiftTo(0, stiffness: 300, damping: 26);
    });
  }

  /// 抬起动画的**当前目标值**；null 表示当前没有抬起动画在跑。
  double? _liftTarget;

  /// 把抬起进度弹向 [target]。
  ///
  /// ## 为什么加了一层「目标没变就不重启」
  ///
  /// `AnimationController.animateWith` 内部会先 `stop()` 掉上一个动画，
  /// 而 `Ticker.start()` 会把**起始时间重置为当前时刻** ——
  /// 于是每次调用都是「从当前值、耗时 0」重新起步。
  ///
  /// 擦洗时每一帧都会调用它，如果每次都重启，
  /// 弹簧就永远只跑完「第一帧」那么一小段时间（实测 `elapsed=0`），
  /// 视觉上就是**透镜根本升不起来**。
  ///
  /// 所以这里加了一层判断：**目标没变就不重启**，
  /// 让弹簧能一口气跑完（收敛过程约 4~5 帧）。
  ///
  /// 补充一个容易误判的点：在 idle phase 调用 `animateWith` 时，
  /// `Ticker.start()` 不会设置 `_startTime`，由首次 tick 兜底赋值 ——
  /// 因此**首次 tick 的 elapsed 恒为 0** 是正常现象，不代表弹簧坏了。
  void _springLiftTo(
    double target, {
    required double stiffness,
    required double damping,
  }) {
    // 已经在朝同一个目标跑了 → 别打断，让它跑完。
    if (_liftTarget == target && _lift.isAnimating) return;
    _liftTarget = target;
    _lift.animateWith(
      SpringSimulation(
        SpringDescription(mass: 1, stiffness: stiffness, damping: damping),
        _lift.value,
        target,
        0,
      ),
    );
  }

  /// 是否正在飞行（起点 → 终点）。
  ///
  /// 飞行途中不能被 [ensureIndex] 打断。
  bool _traveling = false;

  /// 让水滴对齐到某个 tab —— 只在「没在动」的时候。
  ///
  /// 首帧时 [setCenters] 之前 [_centers] 是空的，[travelTo] 直接返回，
  /// 于是水滴会停在 index 0 而不是当前选中项。
  /// 这个方法在每次 build（拿到中心坐标之后）调用一次，
  /// 把这个初始偏差补上。
  void ensureIndex(int index) {
    if (_centers.isEmpty) return;
    // 飞行中 / 擦洗中：不能打断。
    if (_traveling || _scrubX != null) return;
    final int clamped = index.clamp(0, _centers.length - 1);
    if (clamped == _index) return;
    _index = clamped;
    _travelOrigin = clamped;
    _travelOriginX = null;
    // 注意这里**不碰控制器** ——
    // 这个方法在 build 里被调用，改控制器会触发 notifyListeners，
    // 于是引发「build 期间重建」的错误。
    // 只改内部下标即可：位置由 `_centers[_index]` 派生。
  }

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

  /// 归一化横向速度（-1~1）：驱动参考实现里玻璃胶囊的
  /// 「横向拉伸 / 纵向压缩」形变。拖动中跟手更新，松手后弹回 0。
  double get velocity => _velocity.value.clamp(-1.0, 1.0);

  /// 把一个速度值直接写入控制器（拖动跟手时用，不走动画）。
  void _snapVelocity(double value) {
    if (_velocity.isAnimating) _velocity.stop();
    _velocity.value = value.clamp(-1.0, 1.0);
  }

  /// 松手后让速度弹簧衰减回 0。
  void _releaseVelocity() {
    _velocity.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 300, damping: 30),
        _velocity.value,
        0,
        0,
      ),
    );
  }

  /// 测试钩子：直接设定速度。
  void setVelocityForTest(double value) => _snapVelocity(value);

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
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  /// 更新各个 tab 的中心 x。
  void setCenters(List<double> centers) => _centers = centers;

  /// 立即落到某个 tab（无动画）。
  void jumpTo(int index) {
    _index = index.clamp(0, math.max(0, _centers.length - 1));
    _travelOrigin = _index;
    _travelOriginX = null;
    _scrubX = null;
    _liftTarget = null;
    _lift.value = 0;
    _travel.value = 1;
    if (_velocity.isAnimating) _velocity.stop();
    _velocity.value = 0;
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
    _springLiftTo(1, stiffness: 420, damping: 26);

    _animateTravel();
  }

  /// 飞行的弹簧动画（iOS 的 travel spring —— 略微过冲，落位后自然回弹）。
  ///
  /// 进度从 **0** 开始 —— `_travel.value` 是「从出发点到落点的归一化进度」，
  /// 而出发点已经记在 `_travelOrigin` / `_travelOriginX` 里了。
  /// 若从 `_travel.value` 起跳，第二次切换时弹簧就是 1 → 1，水滴根本不动。
  void _animateTravel() {
    _traveling = true;
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
    _springLiftTo(1, stiffness: 420, damping: 26);
  }

  /// 手指沿底栏拖动：水滴跟手。
  bool scrubTo(double localX) {
    if (_centers.isEmpty) return false;
    // 水滴不能被拖出底栏 —— iOS 里透镜始终待在栏内，
    // 拖到头就停在最后一个 tab 上。这里按首尾 tab 的中心做钳制。
    final double next = localX.clamp(_centers.first, _centers.last);
    if (next != _scrubX) {
      // 参考 DampedDragAnimation.updateVelocity 用 VelocityTracker 的
      // 速度 ÷ valueRange 跨度得到「每秒跨几个 tab」，再在 layerBlock 里 ÷10。
      // Flutter 的 scrubTo 逐位移驱动、没有时间戳，无法复刻 VelocityTracker；
      // 因此以「相邻两帧跨了几个 tab」作为归一化速度直接交给形变公式，
      // 不引入任何自定缩放系数（变形系数全部在参考胶囊里按文档给出）。
      final double previous = _scrubX ?? next;
      final double tabWidth = _centers.length > 1
          ? (_centers.last - _centers.first) / (_centers.length - 1)
          : 1.0;
      _snapVelocity((next - previous) / tabWidth);
      _scrubX = next;
      // 主动通知：擦洗位置变了，选中胶囊罩住哪个 tab、
      // 玻璃胶囊的位置与速度，都依赖这个状态。
      // 不通知的话，只有弹簧起跳那几帧会重建，
      // 后面拖动的位置变化就反映不到界面上。
      notifyListeners();
    }
    _springLiftTo(1, stiffness: 520, damping: 30);
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
    _releaseVelocity(); // 参考 onDragStopped：速度衰减，形变回弹。
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

  /// 透镜当前罩住的内容下标。
  ///
  /// 静止/飞行时就是当前落位目标；**擦洗时改为跟随手指最近的 tab** ——
  /// 否则手指滑到隔壁去了，玻璃珠里还显示着上一个 tab 的图标，看起来很假。
  int get contentIndex {
    if (_scrubX == null) return _index;
    return _nearestIndex(_scrubX!);
  }

  /// 玻璃下的内容被折射放大的系数。
  ///
  /// iOS 里被玻璃盖住的图标和文字渲染得**更大** —— 放大来自折射，
  /// 不是选中态。所以这一项只取决于「透镜抬起到什么程度」。
  ///
  /// 上限 1.30 是量出来的：透镜直径 = 图标槽 × 1.35，
  /// 而「图标 + 文字」这一组在正常尺寸下高 38.5pt，
  /// 放大 1.30 后是 50pt —— 正好塞进 51.3pt 的珠子。
  /// 再放大图标就会被圆边裁掉半截，反而看不清是什么图标。
  double get lensMagnification => 1 + 0.30 * lift.clamp(0.0, 1.0);

  bool get _scrubbing => _scrubX != null;

  @override
  void dispose() {
    _lift.removeListener(notifyListeners);
    _travel.removeListener(notifyListeners);
    _velocity.removeListener(notifyListeners);
    _lift.dispose();
    _travel.dispose();
    _velocity.dispose();
    super.dispose();
  }
}
