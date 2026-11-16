import 'package:flutter/physics.dart';

import 'package:flutter/widgets.dart';

/// 玻璃按压时的弹簧回弹。
///
/// 对齐 Compose 参考实现里圆形玻璃那一件的手感：
///
/// ```kotlin
/// val maxScale = (size.width + 16f.dp.toPx()) / size.width
/// val scale = lerp(1f, maxScale, progress)
/// // 按下：animateTo(1f)；抬起：animateTo(0f)
/// // 弹簧：spring(dampingRatio = 0.5f, stiffness = 300f)
/// ```
///
/// Flutter 侧用 `AnimationController.unbounded` + `SpringSimulation`
/// 复刻同一套弹簧参数：[SpringDescription.withDampingRatio] 的
/// `ratio` 就是 Compose 的 `dampingRatio`，`stiffness` 一一对应。
///
/// 之所以用 `unbounded` 控制器：弹簧会冲过目标值再回弹
/// （过冲是液态玻璃手感的来源），有界控制器会把过冲截断。
///
/// [progress] 是弹簧的实时值，可以大于 1 也可以小于 0 ——
/// Compose 里 `lerp(1f, maxScale, progress)` 同样是直接吃这个原始值。
class GlassPress {
  GlassPress({
    required TickerProvider vsync,
    this.dampingRatio = 0.5,
    this.stiffness = 300.0,
  }) : _controller = AnimationController.unbounded(vsync: vsync);

  final double dampingRatio;
  final double stiffness;

  final AnimationController _controller;

  /// 按压进度：0 = 松手，1 = 按到底；弹簧过冲时会超出这个区间。
  double get progress => _controller.value;

  /// 弹簧控制器本身，可直接挂给 `AnimatedBuilder`。
  AnimationController get controller => _controller;

  SpringDescription get _spring => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness,
        ratio: dampingRatio,
      );

  /// 用弹簧把进度推向 [target]（1 = 按到底，0 = 松手）。
  void springTo(double target) {
    _controller.animateWith(
      SpringSimulation(_spring, _controller.value, target, 0),
    );
  }

  void press() => springTo(1);

  void release() => springTo(0);

  void dispose() {
    _controller.dispose();
  }
}
