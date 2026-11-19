import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/glass_drop.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:bililite/widgets/liquid_dock_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏「选中玻璃胶囊」的回归测试。
///
/// 对齐 AndroidLiquidGlass 参考实现 `LiquidBottomTabs`：
///
/// 1. 选中态是一枚**常驻**的胶囊（不是按住才抬起、松手就消失的圆珠）；
/// 2. 它**跟手**左右移动（擦洗时中心跟着手指走）；
/// 3. 按下时按 `78/56` 放大，边缘带**色散**彩边；
/// 4. 图标始终叠在胶囊之上、独立放大，不被折射像替换。
///
/// ## 为什么必须逐帧 pump
///
/// `tester.pump(Duration)` **只产生一帧**。按压 / 落位弹簧需要 4~5 帧收敛，
/// 单次大 pump 跑不完，会出现「代码没问题却断言失败」的假象。
/// 所以这里统一用 [settle] 逐帧推进。
void main() {
  final List<AppSection> tabs = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
  ];

  Widget build({bool compact = false}) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 360,
            child: LiquidGlassDock(
              tabs: tabs,
              standalone: const <AppSection>[AppSection.search],
              active: AppSection.home,
              compact: compact,
              onSelect: (AppSection _) {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(
    WidgetTester tester, {
    int frames = 30,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  testWidgets('静止态：常驻玻璃胶囊存在，且没有抬起圆珠', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    // 参考实现里选中胶囊常驻 —— 静止态也能取到。
    expect(find.byType(ReferenceSelectionPill), findsOneWidget);

    // 旧版的「抬起圆珠」已被移除。
    expect(find.byType(LiquidGlassDrop), findsNothing);

    // 图标与标签只有一份（不再有折射副本造成「双影」）。
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('按下 tab：胶囊按 78/56 放大并带 tint 染色层', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(LiquidGlassDock.dropLabelKey(0))),
    );
    await settle(tester, frames: 40);

    final Finder pill = find.byType(ReferenceSelectionPill);
    expect(pill, findsOneWidget);

    // 外层 Transform 的缩放应收敛到参考的 pressedScale。
    final Transform transform = tester.widget<Transform>(
      find.descendant(of: pill, matching: find.byType(Transform)),
    );
    expect(
      transform.transform.getMaxScaleOnAxis(),
      closeTo(ReferenceDockStyle.pressedScale, 0.12),
      reason: '按下时选中胶囊应放大到 78/56',
    );

    // 色散彩边由 CustomPaint 绘制。
    expect(
      find.descendant(of: pill, matching: find.byType(CustomPaint)),
      findsWidgets,
      reason: '按下的选中胶囊应带色散彩边',
    );

    await gesture.up();
    await settle(tester, frames: 40);
  });

  testWidgets('擦洗：胶囊跟手左右移动', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final Finder pill = find.byType(ReferenceSelectionPill);
    final double before = tester.getCenter(pill).dx;

    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await gesture.moveBy(const Offset(90, 0));
    await settle(tester, frames: 30);

    final double after = tester.getCenter(pill).dx;
    expect(
      (after - before).abs(),
      greaterThan(20),
      reason: '擦洗时选中胶囊应跟着手指移动，before=$before after=$after',
    );

    await gesture.up();
    await settle(tester, frames: 40);
  });

  testWidgets('松手落位后胶囊仍在（常驻）', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await gesture.moveBy(const Offset(60, 0));
    await settle(tester, frames: 30);
    await gesture.up();
    await settle(tester, frames: 60);

    // 与旧版不同：松手后胶囊不消失，只是收回静止形态。
    expect(find.byType(ReferenceSelectionPill), findsOneWidget);
    expect(find.byType(LiquidGlassDrop), findsNothing);
  });

  testWidgets('compact 模式：胶囊常驻，标签行收起文字', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build(compact: true));
    await settle(tester, frames: 40);

    expect(find.byType(ReferenceSelectionPill), findsOneWidget);
    expect(find.text('首页'), findsNothing);
  });
}
