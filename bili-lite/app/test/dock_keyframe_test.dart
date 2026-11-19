import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扁平底栏的视觉验收图。
///
/// 用 `flutter_test` 栅格化而不是手机截图：时间确定、不会抓到过渡中间帧。
/// 每张图只栅格化一次，避免同一个测试里多次 `toImage()` 死锁。
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

  Widget wrap(
    Widget child, {
    double width = 360,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor: brightness == Brightness.dark
            ? const Color(0xFF111319)
            : Colors.white,
      ),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            const Expanded(child: SizedBox.shrink()),
            RepaintBoundary(
              key: const Key('dock-capture'),
              child: SizedBox(
                width: width,
                height: 110,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      final File file = File('../docs/preview/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    });
  }

  Future<void> capture(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.light,
    double width = 360,
    bool pressed = false,
  }) async {
    await tester.pumpWidget(wrap(
      dockFor(AppSection.home),
      width: width,
      brightness: brightness,
    ));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    TestGesture? gesture;
    if (pressed) {
      gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(LiquidGlassDock)) + const Offset(60, 48),
      );
      await gesture.moveBy(const Offset(18, 0));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await dump(tester, name);

    if (gesture != null) {
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('验收图 1：浅色静止态', (tester) async {
    await capture(tester, '106-flat-dock-light');
  });

  testWidgets('验收图 2：深色静止态', (tester) async {
    await capture(
      tester,
      '107-flat-dock-dark',
      brightness: Brightness.dark,
    );
  });

  testWidgets('验收图 3：340pt 窄屏按压态', (tester) async {
    await capture(
      tester,
      '108-flat-dock-narrow',
      width: 340,
      pressed: true,
    );
  });
}
