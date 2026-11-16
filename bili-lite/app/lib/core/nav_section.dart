import 'package:flutter/material.dart';

/// 应用的主导航分区。
///
/// 重构前导航项是一份写死在 `shell_page.dart` 里的 `List<_NavItem>`：
/// 既不能增删、也不能调整顺序，更没法在设置里让用户按自己的习惯排列。
/// PiliPlus 用 `NavBarConfig` 把这件事做成了配置，本项目照此思路把
/// 导航项本身建模，页面只消费 [AppSection] 列表。
enum AppSection {
  home('首页', Icons.home_outlined, Icons.home_rounded),
  search('搜索', Icons.search_outlined, Icons.search_rounded,
      standalone: true),
  library('我的', Icons.bookmarks_outlined, Icons.bookmarks_rounded),
  settings('设置', Icons.settings_outlined, Icons.settings_rounded);

  const AppSection(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.standalone = false,
  });

  /// 底部导航 / 侧边栏显示的文案。
  final String label;

  /// 未选中时的图标。
  final IconData icon;

  /// 选中时的图标。
  final IconData selectedIcon;

  /// 是否是**独立入口**。
  ///
  /// iOS 的底栏有两种形态并存：主标签组（挤在一个玻璃胶囊里）与
  /// 旁边一枚浮起的独立圆形按钮（Safari 的分享、Music 的更多）。
  /// 搜索属于后者 —— 它从胶囊里分出来，固定在底栏右侧，
  /// 不参与标签组的排序，也不跟标签组挤在同一条玻璃里。
  final bool standalone;

  /// 持久化用的稳定标识（不要用 enum 的 index，改顺序会串）。
  String get key => name;

  static AppSection? fromKey(String key) {
    for (final s in AppSection.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}
