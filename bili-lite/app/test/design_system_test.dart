import 'dart:math' as math;

import 'package:bililite/core/nav_section.dart';
import 'package:bililite/core/theme.dart';
import 'package:bililite/core/tokens.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 第十八轮 UI 优化的回归守卫。
///
/// 这一轮把「设计系统」从散落的硬编码收敛成令牌层，本文件固定住
/// 那些**一旦被改回去就会立刻看出退化**的约定。
void main() {
  group('文字层级色', () {
    // WCAG 对比度：给的是 sRGB 相对亮度公式，测试里重算一遍。
    double _lum(Color c) {
      // Flutter 3.0 的 Color.red/green/blue 还是 int（3.27 之后才改成 double）。
      double f(int v) {
        final double x = v / 255.0;
        return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
      }
      return 0.2126 * f(c.red) + 0.7152 * f(c.green) + 0.0722 * f(c.blue);
    }

    double _contrast(Color a, Color b) {
      final double la = _lum(a);
      final double lb = _lum(b);
      final double hi = la > lb ? la : lb;
      final double lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    // 玻璃表面实际渲染出来的色域。
    //
    // 这些值不是手挑的，是从真实截图里**众数采样**出来的：
    // 先用 9x9 邻域众数滤波去掉文字与图标的抗锯齿像素，剩下的就是
    // 玻璃卡片本身的底色。
    //
    // 暗色（docs/preview/12-dark-settings.png）：冷蓝 #344A60 一带，
    // 往右往上是紫调 #63546B —— 玻璃染色后偏亮的那一块是难点。
    const List<Color> darkSurfaces = <Color>[
      Color(0xFF0C2030),
      Color(0xFF31465E),
      Color(0xFF344960),
      Color(0xFF344A5F),
      Color(0xFF344A60),
      Color(0xFF354B60),
      Color(0xFF354C60),
      Color(0xFF354D60),
      Color(0xFF3A5162),
      Color(0xFF3D4A5A),
      Color(0xFF3E4D5C),
      Color(0xFF39344E),
      Color(0xFF5C536D),
      Color(0xFF5F5167),
      Color(0xFF58536E),
      Color(0xFF63546B),
      Color(0xFF50516D),
      Color(0xFF55536E),
    ];

    // 浅色（docs/preview/50-r7-home.png）：纯白到极淡的冷灰。
    const List<Color> lightSurfaces = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFF4F6FA),
      Color(0xFFFBF8FA),
      Color(0xFFF7F2F5),
      Color(0xFFF0EEF2),
      Color(0xFFFAFAFC),
      Color(0xFFF2F1F5),
    ];

    Widget wrap(Brightness b, Widget child) => MaterialApp(
          // 关键：没有这个 key，换亮度时 MaterialApp 会复用同一个 widget
          // 实例，Builder 不重跑，下面的 `late` 变量就会留着上一轮的值
          // —— 断言会拿浅色文字去比暗色玻璃表面，对比度算出来是反的。
          key: ValueKey<Brightness>(b),
          theme: AppTheme.build(b),
          home: Scaffold(body: child),
        );

    Color pick(BuildContext context, Color Function(BuildContext) f) => f(context);

    testWidgets('一级文字在两种模式、玻璃表面上都达到大字号 AAA', (tester) async {
      for (final Brightness b in <Brightness>[Brightness.light, Brightness.dark]) {
        late Color primary;
        await tester.pumpWidget(wrap(b, Builder(builder: (context) {
          primary = pick(context, AppTextColor.primary);
          return const SizedBox.shrink();
        })));
        final List<Color> surfaces =
            b == Brightness.dark ? darkSurfaces : lightSurfaces;
        for (final Color surface in surfaces) {
          // 玻璃染色后无法到 7:1，一级文字都是 16px 以上粗体，
          // 按 WCAG「大字号 4.5:1」判 AA。
          expect(_contrast(primary, surface), greaterThanOrEqualTo(4.5),
              reason: '$b 的一级文字在 $surface 上未达 AA(大字)');
        }
      }
    });

    testWidgets('二级文字在两种模式、玻璃表面上都达到 AA', (tester) async {
      for (final Brightness b in <Brightness>[Brightness.light, Brightness.dark]) {
        late Color secondary;
        await tester.pumpWidget(wrap(b, Builder(builder: (context) {
          secondary = pick(context, AppTextColor.secondary);
          return const SizedBox.shrink();
        })));
        final List<Color> surfaces =
            b == Brightness.dark ? darkSurfaces : lightSurfaces;
        for (final Color surface in surfaces) {
          expect(_contrast(secondary, surface), greaterThanOrEqualTo(4.5),
              reason: '$b 的二级文字在 $surface 上未达 AA');
        }
      }
    });

    testWidgets('三级文字（辅助信息）不低于大字号可读阈值', (tester) async {
      for (final Brightness b in <Brightness>[Brightness.light, Brightness.dark]) {
        late Color tertiary;
        await tester.pumpWidget(wrap(b, Builder(builder: (context) {
          tertiary = pick(context, AppTextColor.tertiary);
          return const SizedBox.shrink();
        })));
        final List<Color> surfaces =
            b == Brightness.dark ? darkSurfaces : lightSurfaces;
        for (final Color surface in surfaces) {
          expect(_contrast(tertiary, surface), greaterThanOrEqualTo(3.0),
              reason: '$b 的三级文字在 $surface 上低于 3:1');
        }
      }
    });

    testWidgets('四级、五级文字各自达到 2:1 / 1.3:1 的底线', (tester) async {
      for (final Brightness b in <Brightness>[Brightness.light, Brightness.dark]) {
        late Color q;
        late Color p;
        await tester.pumpWidget(wrap(b, Builder(builder: (context) {
          q = pick(context, AppTextColor.quaternary);
          p = pick(context, AppTextColor.placeholder);
          return const SizedBox.shrink();
        })));
        final List<Color> surfaces =
            b == Brightness.dark ? darkSurfaces : lightSurfaces;
        for (final Color surface in surfaces) {
          expect(_contrast(q, surface), greaterThanOrEqualTo(2.0),
              reason: '$b 的四级文字在 $surface 上低于 2:1');
          expect(_contrast(p, surface), greaterThanOrEqualTo(1.3),
              reason: '$b 的五级文字在 $surface 上低于 1.3:1');
        }
      }
    });

    testWidgets('层级越浅对比度不反超（单调性）', (tester) async {
      for (final Brightness b in <Brightness>[Brightness.light, Brightness.dark]) {
        final List<Color> surfaces =
            b == Brightness.dark ? darkSurfaces : lightSurfaces;
        await tester.pumpWidget(wrap(b, Builder(builder: (context) {
          final List<double> values = <double>[
            _contrast(AppTextColor.primary(context), surfaces.last),
            _contrast(AppTextColor.secondary(context), surfaces.last),
            _contrast(AppTextColor.tertiary(context), surfaces.last),
            _contrast(AppTextColor.quaternary(context), surfaces.last),
            _contrast(AppTextColor.placeholder(context), surfaces.last),
          ];
          for (var i = 0; i < values.length - 1; i++) {
            expect(values[i], greaterThanOrEqualTo(values[i + 1]),
                reason: '$b 下第 ${i + 1} 档比第 ${i + 2} 档还深，层级反超了');
          }
          return const SizedBox.shrink();
        })));
      }
    });
  });

  group('字号阶梯', () {
    test('语义命名覆盖工程实际用到的全部字号', () {
      // 这一轮之前，工程里实际出现了 17 种字号；现在它们都有语义名字。
      // 这里只固定「阶梯是有序的、且不重复」这个约定。
      final List<double> sizes = <double>[
        AppFontSize.badge,
        AppFontSize.overlay,
        AppFontSize.micro,
        AppFontSize.caption,
        AppFontSize.meta,
        AppFontSize.small,
        AppFontSize.label,
        AppFontSize.body,
        AppFontSize.cardTitle,
        AppFontSize.bodyLarge,
        AppFontSize.sectionTitle,
        AppFontSize.emphasis,
        AppFontSize.detailTitle,
        AppFontSize.title,
        AppFontSize.sheetTitle,
        AppFontSize.headline,
        AppFontSize.appBar,
      ];
      expect(sizes.toSet().length, sizes.length, reason: '字号阶梯不应有重复值');
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]),
            reason: '字号阶梯必须严格递增');
      }
    });

    test('正文可读尺寸不低于 13', () {
      expect(AppFontSize.body, greaterThanOrEqualTo(13));
      expect(AppFontSize.bodyLarge, greaterThanOrEqualTo(14));
    });
  });

  group('底栏排版', () {
    Widget dock(Size size) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: 64,
                child: LiquidGlassDock(
                  tabs: const <AppSection>[
                    AppSection.home,
                    AppSection.library,
                    AppSection.settings,
                  ],
                  standalone: const <AppSection>[AppSection.search],
                  active: AppSection.home,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );

    testWidgets('底栏图标与文字标签不重叠', (tester) async {
      // 回归守卫：上一版 Column 没有 mainAxisSize.min，图标与文字会
      // 溢出叠在一起（见 docs/preview/50-r7-home.png 底部）。
      await tester.binding.setSurfaceSize(const Size(435, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(dock(const Size(435, 64)));
      await tester.pumpAndSettle();

      // 图标直接从 AppSection 取 —— 手写 Icons.bookmarks_rounded 这种
      // 字面量很容易跟实际渲染的图标对不上（未选中时用的是 .icon 字段）。
      const List<AppSection> sections = <AppSection>[
        AppSection.home,
        AppSection.library,
        AppSection.settings,
      ];
      for (final AppSection section in sections) {
        final IconData iconData =
            section == AppSection.home ? section.selectedIcon : section.icon;
        final Finder icon = find.descendant(
          of: find.byType(LiquidGlassDock),
          matching: find.byIcon(iconData),
        );
        final Finder text = find.text(section.label);
        expect(icon, findsWidgets, reason: '应找到 ${section.label} 的图标');
        expect(text, findsOneWidget, reason: '应找到 ${section.label} 的文字标签');

        final Rect iconRect = tester.getRect(icon.first);
        final Rect textRect = tester.getRect(text);
        expect(textRect.top, greaterThanOrEqualTo(iconRect.bottom - 0.5),
            reason: '${section.label} 的文字标签压在了图标上');
      }
    });

    testWidgets('窄屏下底栏也不溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(dock(const Size(320, 64)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
