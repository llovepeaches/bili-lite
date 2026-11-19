import 'package:bililite/core/nav_section.dart';
import 'package:bililite/widgets/liquid_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 扁平底栏的**响应式对齐**与**触控区**回归测试。
///
/// 玻璃已移除，但窄屏下的排布约定仍需固定：
/// 1. 标签组均分左侧区域，每个 tab 保留足够触控宽度；
/// 2. 右侧独立入口不挤压标签文字；
/// 3. compact 模式只收起文字，不裁掉图标。
///
/// 这里不测整个 `ShellPage`（它依赖全局 `prefs`），
/// 而是直接测底栏自身在各种宽度下的几何。
void main() {
  final List<AppSection> threeTabs = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
  ];

  /// 更多 tab —— 用来逼出窄屏下的挤压场景。
  final List<AppSection> manyTabs = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
    AppSection.home,
    AppSection.library,
    AppSection.settings,
  ];

  Widget build({
    required double width,
    List<AppSection>? tabs,
    List<AppSection> standalone = const <AppSection>[AppSection.search],
    bool compact = false,
  }) {
    final List<AppSection> resolvedTabs = tabs ?? threeTabs;
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: LiquidGlassDock(
              tabs: resolvedTabs,
              standalone: standalone,
              active: AppSection.home,
              compact: compact,
              onSelect: (AppSection _) {},
            ),
          ),
        ),
      ),
    );
  }

  /// 每个 tab 的图标（标签行那一份，不含玻璃珠里的折射像）。
  ///
  /// 玻璃珠里的折射像被 `Transform.scale` 放大过，
  /// 所以它比标签行那份**更大** —— 取宽度较小的那一份。
  /// 静止态没有玻璃珠，两份尺寸相同，取哪一个都一样。
  List<Rect> labelIcons(WidgetTester tester, IconData icon) {
    final List<Rect> all = tester
        .widgetList<Icon>(find.byIcon(icon))
        .map((Icon i) => tester.getRect(find.byWidget(i)))
        .toList();
    all.sort((Rect a, Rect b) => a.width.compareTo(b.width));
    return all;
  }

  testWidgets('窄屏（320pt）下每个 tab 仍有 44pt 触控宽度', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build(width: 320));
    await tester.pump();

    // 触控区 = 标签行里那个整格可点的 SizedBox，
    // 它铺满「胶囊宽 ÷ tab 数」，高度是整个胶囊高。
    // 这里量的是**触控区**本身，不是图标。
    final Finder slot = find.ancestor(
      of: find.text('首页'),
      matching: find.byType(SizedBox),
    );
    expect(slot, findsWidgets);

    // 直接量图标所在格子的横向跨度：
    // 相邻两个 tab 的图标中心之差就是每格的宽度。
    final List<Rect> icons = labelIcons(tester, AppSection.home.selectedIcon);
    final List<Rect> libraryIcons = labelIcons(tester, AppSection.library.icon);
    expect(icons, isNotEmpty);
    expect(libraryIcons, isNotEmpty);

    final double cellWidth =
        (libraryIcons.first.center.dx - icons.first.center.dx).abs();
    expect(
      cellWidth,
      greaterThanOrEqualTo(40.0),
      reason: '极窄屏下每格宽度被压得过窄：$cellWidth',
    );
  });

  testWidgets('极窄屏 + 多个 tab 时胶囊仍能容纳标签组', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(build(width: 320, tabs: manyTabs));
    await tester.pump();

    // 标签行每个 tab 都在，且都落在底栏范围内。
    for (final AppSection section in manyTabs) {
      expect(find.text(section.label), findsWidgets);
    }

    final Rect dockRect = tester.getRect(find.byType(LiquidGlassDock));
    final List<Rect> icons = labelIcons(tester, AppSection.home.selectedIcon);
    for (final Rect r in icons) {
      expect(
        dockRect.left,
        lessThanOrEqualTo(r.left),
        reason: '图标越过底栏左边界',
      );
      expect(
        dockRect.right,
        greaterThanOrEqualTo(r.right),
        reason: '图标越过底栏右边界',
      );
    }
  });

  testWidgets('标签行的图标不越出底栏', (WidgetTester tester) async {
    // 静止态没有玻璃珠，标签行那份图标必须老老实实待在底栏里。
    // （抬起态的玻璃珠是**故意**顶出胶囊上沿的，那是另一回事。）
    for (final double width in <double>[320, 375, 414, 768]) {
      await tester.pumpWidget(build(width: width));
      await tester.pump();

      final Rect dockRect = tester.getRect(find.byType(LiquidGlassDock));
      final List<Rect> icons = labelIcons(tester, AppSection.home.selectedIcon);
      for (final Rect r in icons) {
        expect(
          dockRect.top,
          lessThanOrEqualTo(r.top + 0.5),
          reason: '宽度 $width 下标签行图标越出了底栏顶部：${r.top} vs ${dockRect.top}',
        );
        expect(
          dockRect.bottom,
          greaterThanOrEqualTo(r.bottom - 0.5),
          reason: '宽度 $width 下标签行图标越出了底栏底部：${r.bottom} vs ${dockRect.bottom}',
        );
      }
    }
  });

  testWidgets('不同宽度下选中块的横向位置与对应 tab 对齐', (
    WidgetTester tester,
  ) async {
    for (final double width in <double>[320, 375, 414, 768]) {
      await tester.pumpWidget(build(width: width));
      await tester.pumpAndSettle();

      final List<Rect> icons = labelIcons(tester, AppSection.home.selectedIcon);
      expect(icons, isNotEmpty);

      final Rect dockRect = tester.getRect(find.byType(LiquidGlassDock));
      final Rect selection =
          tester.getRect(find.byKey(LiquidGlassDock.selectionKey));

      expect(
        selection.center.dx,
        closeTo(icons.first.center.dx, 2.0),
        reason: '宽度 $width 下选中块没有对齐第一个 tab：$selection',
      );
      expect(
        icons.first.center.dx,
        lessThan(dockRect.right),
      );
    }
  });

  testWidgets('compact 模式下标签收起但图标完整', (WidgetTester tester) async {
    await tester.pumpWidget(build(width: 320, compact: true));
    await tester.pump();

    expect(find.text('首页'), findsNothing);

    final Rect dockRect = tester.getRect(find.byType(LiquidGlassDock));
    final List<Rect> icons = labelIcons(tester, AppSection.home.selectedIcon);
    expect(icons, isNotEmpty);
    for (final Rect r in icons) {
      expect(
        dockRect.top,
        lessThanOrEqualTo(r.top + 0.5),
        reason: 'compact 下图标越出了底栏顶部',
      );
      expect(
        dockRect.bottom,
        greaterThanOrEqualTo(r.bottom - 0.5),
        reason: 'compact 下图标越出了底栏底部',
      );
    }
  });
}
