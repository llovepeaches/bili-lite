import 'package:bililite/core/nav_section.dart';
import 'package:bililite/features/shell/swipe_deck.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 液态玻璃底栏 + 跟手滑动容器的行为单测。
///
/// 这里固定住三条最容易回归的约定：
/// 1. 滑动切页时**只有内容区**位移，底栏不在滑动容器内，因此不会跟着动；
/// 2. 底栏的选中态由 `activeIndex` 决定，与内容区当前页解耦；
/// 3. 页面切换后旧页面仍然挂载（状态保活），不会像 PageView 那样销毁。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// 定位**标签行**里的文字标签。
  ///
  /// 水滴玻璃只罩住图标，文字标签始终在标签行里，所以每个标签唯一；
  /// 这里仍限定在 `LiquidGlassDock` 之内，避免误命中页面上的同名文字。
  Finder tabLabel(String text) => find.descendant(
        of: find.byType(LiquidGlassDock),
        matching: find.text(text),
      ).first;

  group('SwipeDeck', () {
    testWidgets('左滑切到下一页并回调新下标', (tester) async {
      final changes = <int>[];
      final previews = <int>[];

      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 0,
          pages: const <Widget>[
            ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
            ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
            ColoredBox(color: Color(0xFF0000FF), child: SizedBox.expand()),
          ],
          onIndexChanged: changes.add,
          onIndexPreview: previews.add,
        ),
      ));

      await tester.drag(find.byType(SwipeDeck), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(changes, <int>[1]);
    });

    testWidgets('右滑回上一页', (tester) async {
      final changes = <int>[];

      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 1,
          pages: const <Widget>[
            ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
            ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
          ],
          onIndexChanged: changes.add,
        ),
      ));

      await tester.drag(find.byType(SwipeDeck), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(changes, <int>[0]);
    });

    testWidgets('拖动不足阈值时回弹，不切页', (tester) async {
      final changes = <int>[];

      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 0,
          pages: const <Widget>[
            ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
            ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
          ],
          onIndexChanged: changes.add,
        ),
      ));

      await tester.drag(find.byType(SwipeDeck), const Offset(-30, 0));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
    });

    testWidgets('拖动过程中预览下标，吸附后才提交', (tester) async {
      final changes = <int>[];
      final previews = <int>[];

      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 0,
          pages: const <Widget>[
            ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
            ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
          ],
          onIndexChanged: changes.add,
          onIndexPreview: previews.add,
        ),
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(SwipeDeck)));
      await gesture.moveBy(const Offset(-320, 0));
      await tester.pump();
      // 预览已经跟到下一页，但还没提交。
      expect(previews, contains(1));
      expect(changes, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, <int>[1]);
    });

    testWidgets('外部改变 index 时内容区滑过去', (tester) async {
      Widget build(int index) => wrap(
            SwipeDeck(
              key: const ValueKey<String>('deck'),
              index: index,
              pages: const <Widget>[
                ColoredBox(color: Color(0xFFFF0000), child: SizedBox.expand()),
                ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
              ],
              onIndexChanged: (_) {},
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();

      // 第二页应当已经贴到视口里（绿色在正中）。
      final green = tester.getRect(find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF00FF00),
      ));
      expect(green.left, closeTo(0, 1));
    });

    testWidgets('旧页面保持挂载，状态不丢', (tester) async {
      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 0,
          pages: <Widget>[
            const _Counter(),
            const ColoredBox(color: Color(0xFF00FF00), child: SizedBox.expand()),
          ],
          onIndexChanged: (_) {},
        ),
      ));

      // 在第一页里点一下计数器。
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // 切到第二页再切回来，计数应当还在。
      await tester.drag(find.byType(SwipeDeck), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SwipeDeck), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('SwipeDeck 边界', () {
    testWidgets('第一页继续右滑不会越界', (tester) async {
      final changes = <int>[];
      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 0,
          pages: List<Widget>.generate(3, (i) => const ColoredBox(
            color: Color(0xFFFF0000),
            child: SizedBox.expand(),
          )),
          onIndexChanged: changes.add,
        ),
      ));

      await tester.drag(find.byType(SwipeDeck), const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
    });

    testWidgets('最后一页继续左滑不会越界', (tester) async {
      final changes = <int>[];
      await tester.pumpWidget(wrap(
        SwipeDeck(
          index: 2,
          pages: List<Widget>.generate(3, (i) => const ColoredBox(
            color: Color(0xFFFF0000),
            child: SizedBox.expand(),
          )),
          onIndexChanged: changes.add,
        ),
      ));

      await tester.drag(find.byType(SwipeDeck), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
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

      // 胶囊里有标签组的三项。
      //
      // 水滴玻璃**只罩图标**，文字标签留在标签行里，
      // 所以每个标签在整个底栏里只出现一次。
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      // 搜索不在胶囊里，它是右侧那枚独立按钮。
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

    testWidgets('选中独立入口时用粉色透镜图标', (tester) async {
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
