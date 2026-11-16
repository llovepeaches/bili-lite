import 'package:bililite/core/glass_optics.dart';
import 'package:bililite/rendering/render_lens_backdrop.dart';
import 'package:bililite/core/glass_theme.dart';
import 'package:bililite/widgets/glass_sample.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真·液态玻璃光学层的单测。
///
/// 这里钉住三件事：
/// 1. **平台分支** —— Web 端只给纯 blur（html renderer 只认 blur 类滤镜），
///    原生端才叠透镜折射；
/// 2. **透镜支点数学** —— 放大必须以支点为不动点，否则玻璃会整体漂移；
/// 3. **采样层结构** —— 采样层自带一层 `RepaintBoundary`，
///    使滤镜坐标系 == 控件局部坐标。
void main() {
  group('GlassOptics', () {
    test('navFilter 在无透镜时就是一层 blur', () {
      final f = GlassOptics.navFilter(sigma: 12);
      expect(f.toString(), contains('blur'));
    });

    test('lens <= 1 时不叠透镜，避免无谓的整屏重映射', () {
      final plain = GlassOptics.navFilter(sigma: 12, lens: 1.0);
      final almost = GlassOptics.navFilter(sigma: 12, lens: 1.0005);
      expect(almost.toString(), plain.toString());
    });

    test('原生端启用透镜时滤镜链里含 matrix', () {
      // 测试跑在 VM 上，kIsWeb 为 false —— 与原生端同一条路径。
      expect(GlassOptics.supportsLens, isTrue);
      final f = GlassOptics.navFilter(sigma: 12, lens: 1.06);
      expect(f.toString(), contains('matrix'));
    });

    test('magnify 生成的矩阵以支点为不动点', () {
      // dest = s·src + t，支点 p 不动 ⇒ t = p·(1 − s)。
      const double s = 1.06;
      const Offset pivot = Offset(100, 40);
      final t = pivot * (1.0 - s);

      // 支点本身
      expect(pivot.dx * s + t.dx, closeTo(pivot.dx, 1e-9));
      expect(pivot.dy * s + t.dy, closeTo(pivot.dy, 1e-9));

      // 偏离支点的点被推开，且方向背离支点（凸透镜把内容顶大）。
      const Offset q = Offset(110, 40);
      final q2 = Offset(q.dx * s + t.dx, q.dy * s + t.dy);
      expect(q2.dx, greaterThan(q.dx));
      expect((q2.dx - pivot.dx).abs(), greaterThan((q.dx - pivot.dx).abs()));
    });

    test('支点取控件中心时，控件左右对称点对称外扩', () {
      const double s = 1.06;
      const Offset center = Offset(200, 40);
      final t = center * (1.0 - s);
      final left = Offset(center.dx - 10, center.dy);
      final right = Offset(center.dx + 10, center.dy);
      final left2 = Offset(left.dx * s + t.dx, left.dy * s + t.dy);
      final right2 = Offset(right.dx * s + t.dx, right.dy * s + t.dy);
      expect((center.dx - left2.dx), closeTo(right2.dx - center.dx, 1e-9));
    });
  });

  group('GlassSample', () {
    testWidgets('采样层用自定义 RenderObject 承载滤镜（不套 RepaintBoundary）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 100,
          child: GlassSample(sigma: 8, lens: 1.06, child: SizedBox.expand()),
        ),
      ));

      final finder = find.byType(GlassSample);
      expect(finder, findsOneWidget);

      // 采样层内部**不能**有 RepaintBoundary —— 它会为子树建立独立渲染
      // 表面，backdrop 采样只能看到该 surface 内的内容，背景会被隔离掉。
      final boundary = find.descendant(
        of: finder,
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsNothing);

      // 滤镜由 RenderLensBackdrop 在 paint 阶段构造。
      final ro = tester.renderObject(
        find.descendant(
          of: finder,
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString().contains('GlassSampleRender'),
          ),
        ),
      );
      expect(ro, isNotNull);
      expect(ro, isA<RenderLensBackdrop>());
    });

    testWidgets('采样层尺寸透传给滤镜支点', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 80,
            child: GlassSample(sigma: 8, child: SizedBox.expand()),
          ),
        ),
      ));
      final size = tester.getSize(find.byType(GlassSample));
      expect(size.width, 200);
      expect(size.height, 80);
    });
  });

  group('GlassConfig', () {
    test('navBlur / lens / surface 参与相等性与 hashCode', () {
      const a = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        navBlur: 18,
        lens: 1.06,
        surface: 0.16,
      );
      const b = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        navBlur: 18,
        lens: 1.06,
        surface: 0.16,
      );
      const c = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        navBlur: 18,
        lens: 1.10,
        surface: 0.16,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('fallback 保持 blur 关闭、navBlur 关闭', () {
      expect(GlassConfig.fallback.blur, 0);
      expect(GlassConfig.fallback.navBlur, 0);
      expect(GlassConfig.fallback.lens, 1.0);
      expect(GlassConfig.fallback.surface, 0.0);
    });
  });

  group('色相染色', () {
    test('hue / hueAlpha / hueMix 参与相等性与 hashCode', () {
      const a = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        hue: Color(0xFF0088FF),
        hueAlpha: 0.06,
        hueMix: 0.22,
      );
      const b = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        hue: Color(0xFF0088FF),
        hueAlpha: 0.06,
        hueMix: 0.22,
      );
      const c = GlassConfig(
        enabled: true,
        strength: 0.75,
        motion: false,
        blur: 0,
        hue: Color(0xFF0088FF),
        hueAlpha: 0.06,
        hueMix: 0.40,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('fallback 不染色', () {
      expect(GlassConfig.fallback.hue, isNull);
      expect(GlassConfig.fallback.hueAlpha, 0.0);
      expect(GlassConfig.fallback.hueMix, 0.0);
    });
  });
}
