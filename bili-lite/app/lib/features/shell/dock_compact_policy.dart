import 'package:flutter/widgets.dart';

/// 底栏「滚动收起」（compact）的方向判定。
///
/// 对齐 iOS 26 的 `.tabBarMinimizeBehavior(.onScrollDown)`：
/// 内容**向下**滚动时底栏收起（只留图标，标签淡出），
/// 内容**向上**滚动时恢复。
///
/// 为什么单独抽成一个类：
///
/// * **可测**。判定逻辑是纯函数，不依赖 `ShellPage` 那一整套
///   全局 `appState` / `prefs` / `GlassScope`，
///   于是能被单元测试直接覆盖；
/// * **可复用**。底栏和别的 chrome（顶栏、侧栏）都能用同一套判定。
class DockCompactPolicy {
  const DockCompactPolicy();

  /// 根据一条滚动通知算出底栏该处于什么状态。
  ///
  /// 返回 `null` 表示「这条通知不改变状态」。
  ///
  /// * [ScrollUpdateNotification] —— 按 `scrollDelta` 的正负判断：
  ///   正值 = 内容向上移动 = 用户在向下看 → 收起。
  /// * [ScrollEndNotification] —— 惯性滚动结束后，若停在列表**顶部**
  ///   则恢复（iOS 的行为：回到顶部时底栏自动展开）。
  bool? compactFor(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      return compactForDelta(notification.scrollDelta);
    }

    if (notification is ScrollEndNotification) {
      // 只有停在顶部（pixels <= 0）时才强制展开，
      // 否则会打断用户「往下滚 → 收起」的意图。
      if (notification.metrics.pixels <= 0) return false;
    }

    return null;
  }

  /// 纯逻辑版本：一次滚动位移对应什么状态。
  ///
  /// [delta] > 0 表示内容向上移动（滚动位置增大）= 用户在**向下**看，
  /// 对应 iOS 的 onScrollDown → 收起；
  /// [delta] < 0 表示用户在向上看 → 展开。
  ///
  /// [delta] 为 0 或 `null` 表示「不改变状态」。
  bool? compactForDelta(double? delta) {
    if (delta == null || delta == 0) return null;
    return delta > 0;
  }
}
