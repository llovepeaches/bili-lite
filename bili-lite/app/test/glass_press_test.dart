import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/glass_press.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 弹簧工具的单元测试，以及底栏扁平结构守卫。
///
/// 扁平化后底栏不再使用 `GlassPress` 驱动玻璃形变，
/// 但 [GlassPress] 作为独立弹簧工具仍被测到；底栏本身只保留轻量缩放反馈。
void main() {
  group('GlassPress', () {
    testWidgets('按下时进度上升，抬起后回落到 0', (tester) async {
      late GlassPress press;
      await tester.pumpWidget(MaterialApp(
        home: _Host(
          onReady: (GlassPress p) => press = p,
        ),
      ));

      expect(press.progress, 0);

      press.press();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));
      expect(press.progress, greaterThan(0));

      press.release();
      await tester.pumpAndSettle();
      expect(press.progress, closeTo(0, 1e-3));
    });

    testWidgets('弹簧会冲过目标值', (tester) async {
      late GlassPress press;
      await tester.pumpWidget(MaterialApp(
        home: _Host(onReady: (GlassPress p) => press = p),
      ));

      press.press();
      await tester.pump();
      double peak = 0;
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (press.progress > peak) peak = press.progress;
      }
      expect(peak, greaterThan(1.0));
    });

    test('弹簧参数对齐 Compose：ratio 0.5 / stiffness 300', () {
      final GlassPress press = GlassPress(vsync: _FakeTickerProvider());
      expect(press.dampingRatio, 0.5);
      expect(press.stiffness, 300.0);
      press.dispose();
    });
  });

  group('LiquidGlassDock 扁平结构', () {
    const tabs = <AppSection>[
      AppSection.home,
      AppSection.library,
      AppSection.settings,
    ];
    const standalone = <AppSection>[AppSection.search];

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('底栏不挂载任何背景模糊或玻璃透镜', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(LiquidGlassDock.selectionKey), findsOneWidget);
    });

    testWidgets('按下独立入口时只有内容缩放，没有玻璃采样层', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      final Finder icon = find.byIcon(AppSection.search.icon);
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(icon));
      await tester.pump(const Duration(milliseconds: 120));

      final AnimatedScale scale = tester.widget<AnimatedScale>(
        find
            .ancestor(
              of: find.byKey(LiquidGlassDock.itemContentKey(3)),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, lessThan(1.0));
      expect(find.byType(BackdropFilter), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

void _noop(AppSection section) {}

class _Host extends StatefulWidget {
  const _Host({required this.onReady});

  final ValueChanged<GlassPress> onReady;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final GlassPress _press = GlassPress(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_press);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakeTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
