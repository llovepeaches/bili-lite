import 'package:flutter/material.dart';

import 'card_style.dart';

/// 一套断点驱动全部布局：手机用底部导航 + 2 列，平板用侧栏 + 3~4 列，
/// 桌面展开侧栏 + 5 列。所有页面共用，不写平台分支。
class Breakpoints {
  Breakpoints._();

  static const double compact = 600;
  static const double medium = 1000;
  static const double expanded = 1500;

  /// 网格卡片之间的横向间距
  static const double gridSpacing = 14;

  /// 玻璃卡片自身的内边距（封面比卡片窄这么多）
  static const double cardInset = 8;

  /// 卡片文字区预留高度：内边距 + 两行标题 + UP 主行 + 数据行
  static const double cardTextArea = 104;

  /// 沉浸式卡片少一行（弹幕数叠在封面上），文字区相应更矮。
  static const double cardTextAreaImmersive = 88;

  /// 沉浸式 / 紧凑型对应的文字区高度。
  static double textAreaOf(CardStyle style) =>
      style == CardStyle.immersive ? cardTextAreaImmersive : cardTextArea;

  /// 窄屏悬浮 dock 占用的底部空间（dock 本体 68 + 外边距 12）。
  /// 网格需要留出这段，否则最后一行卡片会被 dock 盖住。
  static const double dockBottomInset = 80;

  /// 是否使用左侧 NavigationRail（宽屏）而非底部导航
  static bool useRail(double width) => width >= 700;

  /// 侧栏是否展开显示文字
  static bool railExtended(double width) => width >= 1200;

  /// 视频网格列数
  static int columns(double width) {
    if (width < compact) return 2;
    if (width < medium) return 3;
    if (width < expanded) return 4;
    return 5;
  }

  /// 内容区最大宽度，超宽屏上避免文字被拉得太长
  static double contentMaxWidth(double width) {
    if (width < 1200) return double.infinity;
    return 1600;
  }

  /// 页面水平内边距
  static double gutter(double width) {
    if (width < compact) return 12;
    if (width < medium) return 18;
    return 24;
  }

  /// 详情页在宽屏下改为「左视频信息 + 右评论」双栏。
  ///
  /// 阈值定在 900 而不是 1100：单栏布局里 16:9 的播放器会占满整个视口宽度，
  /// 在 1080 宽的桌面浏览器上播放器高达 600px，下方详情几乎推到屏幕外、
  /// 还要再嵌一层滚动，反而比双栏更难读。
  static bool detailTwoColumn(double width) => width >= 900;

  /// 依据实际卡片宽度算宽高比。
  ///
  /// 玻璃卡片有 8px 内边距，封面比卡片窄，文字区高度基本固定。
  /// 比写死 ratio 更紧凑，所有断点下都不会留白过大。
  ///
  /// 骨架屏（LoadingGrid）与真实网格必须用同一个算法，否则加载完成的瞬间
  /// 卡片会整体缩放一次——重构前两者一个用动态计算、一个写死 0.82。
  ///
  /// [textArea] 由卡片样式决定：沉浸式把弹幕数叠在封面上，少占一行文字。
  static double cardAspectRatio(
    double totalWidth,
    int columns,
    double gutter, {
    double textArea = cardTextArea,
  }) {
    final cardWidth = (totalWidth - gutter * 2 - gridSpacing * (columns - 1)) /
        columns;
    final coverHeight = (cardWidth - cardInset * 2) * 9 / 16;
    return cardWidth / (coverHeight + textArea);
  }
}

/// 导航壳告诉页面「底部有多少空间被悬浮 dock 占用」。
///
/// 窄屏用 `extendBody: true` 让内容延伸到 dock 后面（液态玻璃需要透出背景），
/// 代价是列表末尾会被盖住。页面据此在滚动内容末尾留出等量空白。
///
/// 之所以显式传递而不是让每个页面自己判断宽度：壳层按「整个窗口宽度」决定
/// 是否用侧栏，而网格只知道自己那段宽度，两者在 700~800px 区间会得出
/// 相反结论，底部就会莫名其妙多出一截空白或反之。
class ShellLayout extends InheritedWidget {
  const ShellLayout({
    Key? key,
    required this.usesDock,
    required this.bottomInset,
    required Widget child,
  }) : super(key: key, child: child);

  /// 窄屏底部是否使用悬浮 dock
  final bool usesDock;

  /// dock 占用的底部高度（已含安全区）
  final double bottomInset;

  static const ShellLayout fallback =
      ShellLayout(usesDock: false, bottomInset: 0, child: SizedBox.shrink());

  static ShellLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayout>() ?? fallback;

  @override
  bool updateShouldNotify(ShellLayout oldWidget) =>
      oldWidget.usesDock != usesDock ||
      oldWidget.bottomInset != bottomInset;
}
