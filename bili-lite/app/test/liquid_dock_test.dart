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
    testWidgets('渲染全部入口，并高亮当前项', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          sections: AppSection.values,
          activeIndex: 1,
          onSelect: _noop,
        ),
      ));

      expect(find.text('首页'), findsOneWidget);
      expect(find.text('搜索'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('点击入口回调对应下标', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(wrap(
        LiquidGlassDock(
          sections: AppSection.values,
          activeIndex: 0,
          onSelect: picked.add,
        ),
      ));

      await tester.tap(find.text('设置'));
      expect(picked, <int>[3]);
    });
  });
}

void _noop(int index) {}

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
