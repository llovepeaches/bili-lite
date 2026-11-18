import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 底栏水滴透镜的**动效关键帧**验收。
///
/// 为什么用测试而不是截图脚本：
///
/// * 屏幕抓图的延迟在 500ms 量级，而水滴的飞行只有几百毫秒 —— 抓图**抓不到**中间帧；
/// * `flutter_test` 里可以精确控制时间：`tester.pump(Duration(...))`
///   把动画推进到指定的时刻，于是每一帧都是**确定性的**。
///
/// 实现上的一个坑：`RenderRepaintBoundary.toImage()` 在同一个测试里连着调
/// 多次会**死锁**（Skia 的 raster 线程等一个已经被消费的 future）。
/// 所以这里把每一帧拆成**独立的 testWidgets**，每个用例只栅格化一次。
///
/// 产出的图在仓库的 `docs/preview/` 下，命名 `99-r20-keyframe-*.png`。
void main() {
  final List<AppSection> tabs = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
  ];

  Widget dockFor(AppSection active) => LiquidGlassDock(
        tabs: tabs,
        standalone: const <AppSection>[AppSection.search],
        active: active,
        onSelect: (AppSection _) {},
      );

  Widget wrap(Widget child, {double width = 360}) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            const Expanded(child: SizedBox.shrink()),
            RepaintBoundary(
              key: const Key('dock-capture'),
              child: SizedBox(width: width, height: 96, child: child),
            ),
          ],
        ),
      ),
    );
  }

  /// 把当前渲染结果写成 PNG。
  ///
  /// 必须包在 `tester.runAsync()` 里 —— `toImage()` 是真正的异步 IO
  /// （要等 Skia 的 raster 线程回图），而 `testWidgets` 的默认环境是
  /// **假时钟**：直接 await 它会永远等下去（实测：第一个用例能出图，
  /// 第二个就卡死）。
  ///
  /// `runAsync` 会切到真实的 event loop，假时钟的约束不生效，
  /// 于是栅格化能正常完成。
  Future<void> dump(WidgetTester tester, String name) async {
    final RenderRepaintBoundary boundary =
        tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('dock-capture')),
    );

    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final File file = File('docs/preview/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    });
  }

  /// 推进到第 [step] 个关键帧并截图。
  ///
  /// [step] 为 0 表示静止态（动画已结束），> 0 表示飞行开始后第 step 个 40ms 帧。
  Future<void> captureFlight(WidgetTester tester, int step) async {
    await tester.pumpWidget(wrap(dockFor(AppSection.home)));
    // 先让静止态落定。
    await tester.pump(const Duration(milliseconds: 600));

    // 切换选中项 → 水滴飞向第三个 tab。
    await tester.pumpWidget(wrap(dockFor(AppSection.settings)));

    for (int i = 0; i < step; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await dump(
      tester,
      step == 0 ? '99-r20-keyframe-rest' : '99-r20-keyframe-$step',
    );
  }

  testWidgets('关键帧 0：静止态', (WidgetTester tester) async {
    await captureFlight(tester, 0);
  });

  testWidgets('关键帧 1：刚起飞', (WidgetTester tester) async {
    await captureFlight(tester, 1);
  });

  testWidgets('关键帧 2：飞行中（拉伸）', (WidgetTester tester) async {
    await captureFlight(tester, 2);
  });

  testWidgets('关键帧 4：飞行中段', (WidgetTester tester) async {
    await captureFlight(tester, 4);
  });

  testWidgets('关键帧 6：接近落位（压扁）', (WidgetTester tester) async {
    await captureFlight(tester, 6);
  });

  testWidgets('关键帧 8：落位回弹', (WidgetTester tester) async {
    await captureFlight(tester, 8);
  });

  /// 拖动擦洗的关键帧：按住底栏横向拖动，水滴应当**跟手**移动。
  Future<void> captureScrub(WidgetTester tester, int step) async {
    await tester.pumpWidget(wrap(dockFor(AppSection.home)));
    await tester.pump(const Duration(milliseconds: 600));

    // 按在**胶囊**上，而不是整个底栏（底栏右边还挂着一枚独立的搜索按钮，
    // 用整个 widget 的中心会偏右，拖出胶囊范围）。
    final TestGesture gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
    );
    await tester.pump(const Duration(milliseconds: 60));

    for (int i = 0; i < step; i++) {
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }

    await dump(tester, '100-r20-scrub-$step');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('擦洗关键帧 1：拖动中（水滴跟手）', (WidgetTester tester) async {
    await captureScrub(tester, 1);
  });

  testWidgets('擦洗关键帧 3：拖到第二个 tab', (WidgetTester tester) async {
    await captureScrub(tester, 3);
  });

  testWidgets('擦洗关键帧 5：拖到第三个 tab', (WidgetTester tester) async {
    await captureScrub(tester, 5);
  });
}
