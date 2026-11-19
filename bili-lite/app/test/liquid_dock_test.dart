import 'package:bililite/core/nav_section.dart';
import 'package:bililite/features/shell/page_stack.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扁平底栏与静态内容容器的行为单测。
///
/// 固定三条约定：
/// 1. 内容区没有左右滑动切页手势；
/// 2. 页面切换只由外部导航驱动，旧页面状态仍保留；
/// 3. 底栏只渲染标签组与独立入口，点按回调对应入口。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Finder tabLabel(String text) => find
      .descendant(
        of: find.byType(LiquidGlassDock),
        matching: find.text(text),
      )
      .first;

  group('PageStack', () {
    testWidgets('左右拖动不会切页，第一页保持原位', (tester) async {
      await tester.pumpWidget(wrap(const PageStack(
        index: 0,
        pages: <Widget>[
          Center(child: Text('第一页')),
          Center(child: Text('第二页')),
        ],
      )));

      final Rect before = tester.getRect(find.text('第一页'));
      await tester.drag(find.byType(PageStack), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('第一页'), findsOneWidget);
      expect(tester.getRect(find.text('第一页')), before);
    });

    testWidgets('外部切换页面后旧页面状态仍保留', (tester) async {
      Widget build(int index) => wrap(PageStack(
            index: index,
            pages: <Widget>[
              const _Counter(),
              const Center(child: Text('第二页')),
            ],
          ));

      await tester.pumpWidget(build(0));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);

      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('LiquidGlassDock', () {
    const tabs = <AppSection>[
      AppSection.home,
      AppSection.library,
      AppSection.settings,
    ];
    const standalone = <AppSection>[AppSection.search];

    testWidgets('胶囊只渲染标签组，独立入口单独渲染', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      expect(find.text('首页'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('搜索'), findsNothing);
      expect(find.byIcon(AppSection.search.icon), findsOneWidget);
    });

    testWidgets('点击标签回调对应的入口', (tester) async {
      final picked = <AppSection>[];
      await tester.pumpWidget(wrap(
        LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: picked.add,
        ),
      ));

      await tester.tap(find.text('设置'));
      expect(picked, <AppSection>[AppSection.settings]);
    });

    testWidgets('点击独立圆形按钮回调搜索', (tester) async {
      final picked = <AppSection>[];
      await tester.pumpWidget(wrap(
        LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: picked.add,
        ),
      ));

      await tester.tap(find.byIcon(AppSection.search.icon));
      expect(picked, <AppSection>[AppSection.search]);
    });

    testWidgets('选中独立入口时用对应图标', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.search,
          onSelect: _noop,
        ),
      ));

      expect(find.byIcon(AppSection.search.selectedIcon), findsOneWidget);
      expect(find.byIcon(AppSection.search.icon), findsNothing);
    });

    testWidgets('独立入口不在胶囊内：位置在胶囊右侧', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      final capsule = tester.getRect(tabLabel('首页'));
      final button = tester.getRect(find.byIcon(AppSection.search.icon));
      expect(button.left, greaterThan(capsule.right));
    });
  });
}

void _noop(AppSection section) {}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => setState(() => _count++),
        child: Text('$_count'),
      ),
    );
  }
}
