import 'package:bililite/features/shell/dock_compact_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏「滚动收起」方向判定的回归测试。
///
/// 这段判定是纯逻辑，抽成了 [DockCompactPolicy]，
/// 所以不需要 `ShellPage` 那一整套全局依赖就能覆盖。
///
/// 这里固化的都是实测踩过的坑：
/// * `UserScrollNotification` 在 Linux 桌面的鼠标滚轮下**一条都不派发**，
///   所以判定必须基于 `ScrollUpdateNotification.scrollDelta`；
/// * 第一版用 `notification.depth != 0` 做过滤，把所有通知都丢掉了。
void main() {
  const DockCompactPolicy policy = DockCompactPolicy();

  group('DockCompactPolicy 方向判定', () {
    test('内容向下滚（delta > 0）→ 收起', () {
      expect(policy.compactForDelta(120), isTrue);
    });

    test('内容向上滚（delta < 0）→ 展开', () {
      expect(policy.compactForDelta(-120), isFalse);
    });

    test('零位移不改变状态', () {
      expect(policy.compactForDelta(0), isNull);
    });

    test('null 位移不改变状态', () {
      expect(policy.compactForDelta(null), isNull);
    });
  });

  group('DockCompactPolicy 通知处理', () {
    testWidgets('ScrollUpdateNotification 按位移判定', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      );

      ScrollUpdateNotification make(double d) => ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 2000,
              pixels: 0,
              viewportDimension: 800,
              axisDirection: AxisDirection.down,
            ),
            context: ctx,
            scrollDelta: d,
          );

      expect(policy.compactFor(make(120)), isTrue);
      expect(policy.compactFor(make(-120)), isFalse);
      expect(policy.compactFor(make(0)), isNull);
    });

    testWidgets('滚回顶部时强制展开', (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      );

      ScrollEndNotification end(double pixels) => ScrollEndNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 2000,
              pixels: pixels,
              viewportDimension: 800,
              axisDirection: AxisDirection.down,
            ),
            context: ctx,
          );

      // 停在顶部 → 展开。
      expect(policy.compactFor(end(0)), isFalse);
      // 停在中部 → 不改变状态。
      expect(policy.compactFor(end(600)), isNull);
    });
  });
}
