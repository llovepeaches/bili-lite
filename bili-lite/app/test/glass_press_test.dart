import 'package:bililite/widgets/glass_press.dart';
import 'package:bililite/widgets/glass_sample.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:bililite/core/nav_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏「共享 backdrop + 弹簧按压」结构的单测。
///
/// 这里钉住三件事：
/// 1. **共享采样** —— 整条底栏只做一次 `BackdropFilter`，两件玻璃各自
///    再套一层透镜；兄弟玻璃因此看到的是同一份背景，不会互相采样；
/// 2. **弹簧参数** —— 按压回弹对齐 Compose 的
///    `spring(dampingRatio = 0.5f, stiffness = 300f)`；
/// 3. **按压真的把玻璃本体撑大** —— 不是只放大图标。
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
      // 第一次 pump 只把 ticker 启动起来（这一帧的 elapsed 还是 0），
      // 第二次 pump 弹簧才真正推进。
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));
      expect(press.progress, greaterThan(0));

      press.release();
      await tester.pumpAndSettle();
      expect(press.progress, closeTo(0, 1e-3));
    });

    testWidgets('弹簧会冲过目标值（过冲是液态手感的来源）', (tester) async {
      late GlassPress press;
      await tester.pumpWidget(MaterialApp(
        home: _Host(onReady: (GlassPress p) => press = p),
      ));

      press.press();
      await tester.pump();
      // 继续推进若干帧，采样是否出现过 > 1 的值。
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

  group('LiquidGlassDock 共享 backdrop', () {
    const tabs = <AppSection>[
      AppSection.home,
      AppSection.library,
      AppSection.settings,
    ];
    const standalone = <AppSection>[AppSection.search];

    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('整条底栏只有一处共享的 BackdropFilter', (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      // 一层共享采样 = 一次背景读取；两件玻璃各自的透镜在它内部。
      expect(find.byType(BackdropFilter), findsOneWidget);
      // 两件玻璃各有一套透镜采样层（胶囊 + 圆形）。
      expect(find.byType(GlassSample), findsNWidgets(2));
    });

    testWidgets('按压圆形按钮时玻璃本体被撑大（不是只放大图标）',
        (tester) async {
      await tester.pumpWidget(wrap(
        const LiquidGlassDock(
          tabs: tabs,
          standalone: standalone,
          active: AppSection.home,
          onSelect: _noop,
        ),
      ));

      // 圆形玻璃的采样层尺寸 = 按钮直径。
      final double before = tester
          .getSize(
            find.descendant(
              of: find.byType(GlassSample).last,
              matching: find.byType(SizedBox),
            ).first,
          )
          .width;

      final Finder icon = find.byIcon(AppSection.search.icon);
      final Offset center = tester.getCenter(icon);
      final TestGesture gesture =
          await tester.startGesture(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      final double after = tester
          .getSize(
            find.descendant(
              of: find.byType(GlassSample).last,
              matching: find.byType(SizedBox),
            ).first,
          )
          .width;

      expect(after, greaterThan(before));
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
