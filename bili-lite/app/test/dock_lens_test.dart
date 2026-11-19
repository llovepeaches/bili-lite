import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扁平底栏的选中态回归测试。
///
/// 这里固定四件事：
/// 1. 底栏不再挂载任何玻璃 / 模糊 / 透镜组件；
/// 2. 选中态是一枚常驻的浅粉圆角实底；
/// 3. 按下条目有克制的缩放反馈；
/// 4. 擦洗时选中块跟手移动，松手后仍常驻。
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

  testWidgets('静止态：浅粉选中块常驻，且完全没有玻璃效果', (tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 20);

    expect(find.byKey(LiquidGlassDock.selectionKey), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('按下 tab：内容区有缩放反馈，不出现玻璃高光', (tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 20);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(LiquidGlassDock.dropLabelKey(0))),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final AnimatedScale scale = tester.widget<AnimatedScale>(
      find
          .ancestor(
            of: find.byKey(LiquidGlassDock.itemContentKey(0)),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );
    expect(scale.scale, lessThan(1.0));
    expect(find.byType(BackdropFilter), findsNothing);

    await gesture.up();
    await settle(tester, frames: 20);
  });

  testWidgets('擦洗：选中块跟手左右移动', (tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 20);

    final Finder selection = find.byKey(LiquidGlassDock.selectionKey);
    final double before = tester.getCenter(selection).dx;

    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await gesture.moveBy(const Offset(90, 0));
    await settle(tester, frames: 30);

    final double after = tester.getCenter(selection).dx;
    expect(
      (after - before).abs(),
      greaterThan(20),
      reason: '擦洗时选中块应跟着手指移动，before=$before after=$after',
    );

    await gesture.up();
    await settle(tester, frames: 30);
  });

  testWidgets('松手落位后选中块仍在（常驻）', (tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 20);

    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await gesture.moveBy(const Offset(60, 0));
    await settle(tester, frames: 20);
    await gesture.up();
    await settle(tester, frames: 30);

    expect(find.byKey(LiquidGlassDock.selectionKey), findsOneWidget);
  });

  testWidgets('compact 模式：选中块常驻，标签行收起文字', (tester) async {
    await tester.pumpWidget(build(compact: true));
    await settle(tester, frames: 20);

    expect(find.byKey(LiquidGlassDock.selectionKey), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
