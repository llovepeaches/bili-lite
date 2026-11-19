import 'package:bililite/widgets/liquid_dock_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidLiquidGlass dock 参考参数', () {
    test('尺寸、模糊与透镜常量与参考实现一致', () {
      expect(ReferenceDockStyle.barHeight, 64);
      expect(ReferenceDockStyle.inset, 4);
      expect(ReferenceDockStyle.blur, 8);
      expect(ReferenceDockStyle.lensRefraction, 24);
      expect(ReferenceDockStyle.pressedScale, closeTo(78 / 56, 0.0001));
    });

    test('容器表面色为参考实现的 40% 不透明容器色', () {
      final light = referenceDockContainerGradient(false).colors.first;
      final dark = referenceDockContainerGradient(true).colors.first;

      expect(light, const Color(0x66FAFAFA));
      expect(dark, const Color(0x66121212));
      expect(light.alpha / 255, closeTo(0.4, 0.01));
      expect(dark.alpha / 255, closeTo(0.4, 0.01));
    });

    test('强调色按明暗主题取参考蓝', () {
      expect(referenceDockAccent(false), const Color(0xFF0088FF));
      expect(referenceDockAccent(true), const Color(0xFF0091FF));
    });
  });

  testWidgets('选中玻璃胶囊按下时按 78/56 放大', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 80,
          height: 54,
          child: ReferenceSelectionPill(
            progress: 1,
            accent: referenceDockAccent(false),
            dark: false,
          ),
        ),
      ),
    ));

    final Transform transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(ReferenceSelectionPill),
        matching: find.byType(Transform),
      ),
    );
    expect(
      transform.transform.getMaxScaleOnAxis(),
      closeTo(ReferenceDockStyle.pressedScale, 0.0001),
    );
  });

  testWidgets('选中玻璃胶囊随横向速度做液态形变', (tester) async {
    // 满速向右拖：横向拉伸（scaleX > 基准），纵向压缩（scaleY < 基准）。
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 80,
          height: 54,
          child: ReferenceSelectionPill(
            progress: 1,
            velocity: 1,
            accent: referenceDockAccent(false),
            dark: false,
          ),
        ),
      ),
    ));

    final Transform transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(ReferenceSelectionPill),
        matching: find.byType(Transform),
      ),
    );
    // Matrix4.diagonal3Values(sx, sy, 1)：[0] 是 scaleX，[5] 是 scaleY。
    final double scaleX = transform.transform[0];
    final double scaleY = transform.transform[5];
    expect(scaleX, greaterThan(ReferenceDockStyle.pressedScale));
    expect(scaleY, lessThan(ReferenceDockStyle.pressedScale));
  });
}
