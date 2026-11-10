/// 一套断点驱动全部布局：手机用底部导航 + 2 列，平板用侧栏 + 3~4 列，
/// 桌面展开侧栏 + 5 列。所有页面共用，不写平台分支。
class Breakpoints {
  Breakpoints._();

  static const double compact = 600;
  static const double medium = 1000;
  static const double expanded = 1500;

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

  /// 详情页在宽屏下改为「左视频信息 + 右评论」双栏
  static bool detailTwoColumn(double width) => width >= 1100;
}
