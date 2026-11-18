import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏 compact（滚动收起）模式的回归测试。
///
/// iOS 26 的 `.tabBarMinimizeBehavior(.onScrollDown)`：
/// **向下滚动**时底栏收起（只留图标，标签淡出），
/// **向上滚动**时恢复（标签重新出现）。
///
/// 这里不测整个 `ShellPage`（它依赖全局 `prefs`），
/// 而是测底栏自己的 compact 行为 —— 收起时标签必须真的消失，
/// 且不能把图标裁掉。
void main() {
  final List<AppSection> tabs = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
  ];

  Widget build({required bool compact}) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        // 不给固定高度 —— 底栏自己按 compact 状态决定高度，
        // 外层再套一个 SizedBox 会把这个高度差盖掉。
        body: Align(
          alignment: Alignment.bottomCenter,
          child: LiquidGlassDock(
            tabs: tabs,
            standalone: const <AppSection>[],
            active: AppSection.home,
            compact: compact,
            onSelect: (AppSection _) {},
          ),
        ),
      ),
    );
  }

  testWidgets('compact 时底栏变矮', (WidgetTester tester) async {
    await tester.pumpWidget(build(compact: false));
    await tester.pump();
    final double fullHeight = tester.getSize(find.byType(LiquidGlassDock)).height;

    await tester.pumpWidget(build(compact: true));
    await tester.pump();
    final double compactHeight =
        tester.getSize(find.byType(LiquidGlassDock)).height;

    expect(
      compactHeight,
      lessThan(fullHeight),
      reason: 'compact 模式底栏应当更矮',
    );
  });

  testWidgets('compact 时文字标签不再渲染', (WidgetTester tester) async {
    await tester.pumpWidget(build(compact: false));
    await tester.pump();
    expect(find.text('首页'), findsOneWidget);

    await tester.pumpWidget(build(compact: true));
    await tester.pump();
    expect(
      find.text('首页'),
      findsNothing,
      reason: 'compact 模式下标签应当收起',
    );
    // 图标还在（标签行一份 + 水滴玻璃里一份）。
    expect(find.byIcon(AppSection.home.selectedIcon), findsWidgets);
  });

  testWidgets('compact 时图标没有被裁掉', (WidgetTester tester) async {
    await tester.pumpWidget(build(compact: true));
    await tester.pump();

    // 选中图标渲染两次：标签行一份 + 水滴玻璃里一份。
    final List<Rect> iconRects = tester
        .widgetList<Icon>(find.byIcon(AppSection.home.selectedIcon))
        .map((Icon icon) => tester.getRect(find.byWidget(icon)))
        .toList();
    expect(iconRects, isNotEmpty);

    final Rect dockRect = tester.getRect(find.byType(LiquidGlassDock));
    for (final Rect r in iconRects) {
      // 每一份图标都必须完整落在底栏范围内，不能被裁掉。
      expect(dockRect.top, lessThanOrEqualTo(r.top),
          reason: '图标顶部越界了');
      expect(dockRect.bottom, greaterThanOrEqualTo(r.bottom),
          reason: '图标底部越界了');
    }
  });
}
