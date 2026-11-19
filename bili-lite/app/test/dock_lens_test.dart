import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/glass_drop.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏「抬起态大圆透镜」的回归测试。
///
/// 参考图（抬起态）里那颗玻璃珠有三个硬性特征：
///
/// 1. 它是**圆**的，不是胶囊；
/// 2. 它**顶出胶囊上沿** —— 画在胶囊的裁剪层之外；
/// 3. 透镜内部罩住的是「图标 + 文字」整组，一起被放大折射。
///
/// 落位之后透镜必须**收起**，让位给静止态的柔边光晕。
///
/// ## 为什么必须逐帧 pump
///
/// `tester.pump(Duration)` **只产生一帧**。抬起态的弹簧需要
/// 「travel 落位 → lift 起跳 → 4~5 帧收敛」，单次大 pump 跑不完，
/// 于是会出现「明明代码没问题，测试却断言失败」的假象。
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

  /// 逐帧推进，让弹簧真正收敛。
  Future<void> settle(
    WidgetTester tester, {
    int frames = 30,
    Duration step = const Duration(milliseconds: 16),
  }) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  /// 按住底栏横向拖动，**保持手指不松开**。
  ///
  /// 抬起态的几何与内容断言都要在按住状态下做：
  /// 一松手就会触发落位收起，透镜随即消失。
  Future<TestGesture> pressAndScrub(
    WidgetTester tester, {
    double dx = 60,
  }) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(Offset(dx, 0));
    await settle(tester);
    return gesture;
  }

  /// 找出离透镜中心最近的那个 tab 下标。
  ///
  /// 透镜在擦洗时**跟着手指走**，内容取的是最近的 tab ——
  /// 所以断言必须按位置反推，不能写死文案。
  int nearestTab(WidgetTester tester, double dx) {
    int best = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < tabs.length; i++) {
      final Finder label = find.byKey(LiquidGlassDock.dropLabelKey(i));
      if (label.evaluate().isEmpty) continue;
      final double d = (tester.getCenter(label).dx - dx).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  testWidgets('静止态：没有透镜，只有柔边光晕', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    // 抬起态透镜必须收起 —— 底栏不能长期停在一颗悬空玻璃珠上。
    expect(find.byType(LiquidGlassDrop), findsNothing);

    // 静止态由柔边光晕托底。
    expect(find.byType(SelectedGlow), findsOneWidget);
  });

  testWidgets('抬起态：透镜是圆的且顶出胶囊上沿', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);

    expect(find.byType(LiquidGlassDrop), findsOneWidget);

    final Rect lens = tester.getRect(find.byType(LiquidGlassDrop));
    final Rect capsule =
        tester.getRect(find.byKey(LiquidGlassDock.capsuleKey));

    // 圆形：宽高相等。
    expect(
      lens.width,
      closeTo(lens.height, 0.5),
      reason: '抬起态透镜应当是圆形玻璃珠，而不是胶囊',
    );

    // 顶出胶囊上沿。
    //
    // 基准必须用**胶囊本体**，不能用光晕顶边：
    // 光晕以图标槽为中心、纵向比图标槽高 15pt，
    // 它的顶边天然比胶囊上沿高 4.5pt，拿它当代理数学上不可能成立。
    // 而且抬起时光晕是完全隐去的（opacity→0，节点被移除），根本取不到。
    expect(
      lens.top,
      lessThan(capsule.top),
      reason: '透镜没有顶出胶囊上沿：lens.top=${lens.top} '
          'capsule.top=${capsule.top}',
    );

    // 透镜盖住了胶囊的横向位置：中心落在胶囊范围内。
    expect(lens.center.dx, greaterThan(capsule.left));
    expect(lens.center.dx, lessThan(capsule.right));

    // 透镜比图标槽大（它作为「放大镜」的前提）。
    final double iconSlot = 38.0;
    expect(lens.width, greaterThan(iconSlot));

    await gesture.up();
  });

  testWidgets('抬起态：透镜内部同时含图标与文字', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);

    expect(find.byType(LiquidGlassDrop), findsOneWidget);

    // 透镜里的内容是一整组「图标 + 标签」。
    // 标签文字因此会出现**两次**：标签行里一次，透镜折射像里一次。
    final Rect lens = tester.getRect(find.byType(LiquidGlassDrop));
    final int index = nearestTab(tester, lens.center.dx);
    final String label = tabs[index].label;

    expect(find.text(label), findsWidgets);

    // 透镜内部必须真的画了那个标签 —— 不是只有一个图标。
    //
    // 注意：色散是靠 **RGB 三层叠绘**（原色 + 青 + 品红）实现的，
    // 所以同一份内容在透镜里会出现 3 次。
    expect(
      find.descendant(
        of: find.byType(LiquidGlassDrop),
        matching: find.text(label),
      ),
      findsNWidgets(3),
      reason: '透镜内部应当把标签画成三层色散（原色 + 青 + 品红）',
    );

    expect(
      find.descendant(
        of: find.byType(LiquidGlassDrop),
        matching: find.byIcon(tabs[index].selectedIcon),
      ),
      findsNWidgets(3),
    );

    // 标签行里那一份必须是可交互的（有独立 key），
    // 且与透镜里的折射像区分得开。
    expect(find.byKey(LiquidGlassDock.dropLabelKey(index)), findsOneWidget);

    await gesture.up();
  });

  testWidgets('抬起态：透镜内的内容被折射放大', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);

    // 透镜内部套着一层 Transform.scale（折射放大），抬起后应当明显大于 1。
    final Iterable<Transform> transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(LiquidGlassDrop),
        matching: find.byType(Transform),
      ),
    );
    double maxScale = 1;
    for (final Transform t in transforms) {
      final double s = t.transform.getMaxScaleOnAxis();
      if (s > maxScale) maxScale = s;
    }
    expect(maxScale, greaterThan(1.2),
        reason: '玻璃珠内部的内容应当被折射放大，实测最大缩放 $maxScale');

    await gesture.up();
  });

  testWidgets('抬起态：透镜不越出底栏左右边界', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);

    final Rect dock = tester.getRect(find.byType(LiquidGlassDock));
    final Rect lens = tester.getRect(find.byType(LiquidGlassDrop));

    expect(lens.left, greaterThanOrEqualTo(dock.left - 0.5));
    expect(lens.right, lessThanOrEqualTo(dock.right + 0.5));

    await gesture.up();
  });

  testWidgets('松手落位后透镜收起', (WidgetTester tester) async {
    await tester.pumpWidget(build());
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);
    expect(find.byType(LiquidGlassDrop), findsOneWidget);

    // 松手 → 落位 → 收起。这条链路要跑好几帧，单次 pump 不够。
    await gesture.up();
    await settle(tester, frames: 60);

    expect(find.byType(LiquidGlassDrop), findsNothing);
    expect(find.byType(SelectedGlow), findsOneWidget);
  });

  testWidgets('compact 模式：透镜内只有图标，没有文字', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build(compact: true));
    await settle(tester, frames: 40);

    final TestGesture gesture = await pressAndScrub(tester);

    expect(find.byType(LiquidGlassDrop), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LiquidGlassDrop),
        matching: find.text('首页'),
      ),
      findsNothing,
    );

    await gesture.up();
  });
}
