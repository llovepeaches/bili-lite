import 'package:flutter/material.dart';

import '../../core/nav_section.dart';
import '../home/home_view.dart';
import '../library/library_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';

/// 把导航入口映射为壳内页面。
///
/// 页面实例仍由各 feature 自己负责状态；这里只集中「入口 → 页面组件」
/// 的对应关系，避免壳页同时承担页面装配与导航手势职责。
List<Widget> pagesForSections(List<AppSection> sections) {
  return sections.map((section) {
    switch (section) {
      case AppSection.home:
        return const HomeView();
      case AppSection.search:
        return const SearchView();
      case AppSection.library:
        return const LibraryPage();
      case AppSection.settings:
        return const SettingsPage();
    }
  }).toList();
}
