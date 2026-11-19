import 'package:flutter/material.dart';

import '../../core/nav_section.dart';
import '../../core/responsive.dart';
import '../../state/globals.dart';
import '../../widgets/liquid_dock.dart';
import 'dock_compact_policy.dart';
import 'glass_sidebar.dart';
import 'page_stack.dart';
import 'shell_page_factory.dart';

/// 导航壳：窄屏扁平底部导航，宽屏扁平侧栏。
///
/// 内容区用 [PageStack] 承载：页面只由底栏 / 侧栏点按切换，
/// **不提供左右滑动切页**；所有页面保持挂载以保留滚动位置和输入状态。
///
/// 导航项不再写死：来自 `AppPrefs.sections`，用户可以在设置里增删与排序
/// （参考 PiliPlus 的 `NavBarConfig`）。这里用 [AppSection] 而不是下标来
/// 记录当前选中项 —— 顺序变了之后按下标记忆会选错页面。
///
/// 页面装配在 `shell_page_factory.dart`，宽屏侧栏在 `glass_sidebar.dart`；
/// 本文件只负责壳状态、页面切换与窄 / 宽屏布局编排。
class ShellPage extends StatefulWidget {
  const ShellPage({Key? key}) : super(key: key);

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  AppSection? _current;

  /// 底栏是否处于 compact 态（滚动收起后只留图标）。
  bool _compact = false;

  /// 滚动收起的方向判定（纯逻辑，抽出来是为了能单独测）。
  static const DockCompactPolicy _compactPolicy = DockCompactPolicy();

  /// 视觉顺序：标签组在前，**独立入口固定在最右**。
  List<AppSection> get _sections => <AppSection>[
        ...prefs.tabSections,
        ...prefs.standaloneSections,
      ];

  AppSection get _active =>
      _current ?? (_sections.isEmpty ? AppSection.home : _sections.first);

  void _select(AppSection section) {
    if (_active == section) return;
    setState(() {
      _current = section;
    });
  }

  /// 内容区滚动时，底栏跟随收起 / 展开。
  bool _onScroll(ScrollNotification notification) {
    final bool? next = _compactPolicy.compactFor(notification);
    if (next == null) return false;
    _setCompact(next);
    return false;
  }

  void _setCompact(bool value) {
    if (_compact == value) return;
    setState(() => _compact = value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final sections = _sections;
        if (sections.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('至少需要保留一个导航入口')),
          );
        }
        final stackKey = ValueKey<String>(sections.map((e) => e.key).join(','));
        final activeIndex = _indexOf(sections, _active);

        return LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (!Breakpoints.useRail(width)) {
            final media = MediaQuery.of(context);
            final bottomInset =
                Breakpoints.dockBottomInset + media.padding.bottom;
            return ShellLayout(
              usesDock: true,
              bottomInset: bottomInset,
              child: WillPopScope(
                onWillPop: _handleWillPop,
                child: Scaffold(
                  extendBody: true,
                  body: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: _deck(sections, stackKey, activeIndex),
                  ),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: LiquidGlassDock(
                          tabs: prefs.tabSections,
                          standalone: prefs.standaloneSections,
                          active: _active,
                          onSelect: _select,
                          compact: _compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final extended = Breakpoints.railExtended(width);
          return ShellLayout(
            usesDock: false,
            bottomInset: 0,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  GlassSidebar(
                    sections: sections,
                    active: _active,
                    extended: extended,
                    onSelect: _select,
                  ),
                  Expanded(
                    child: _deck(sections, stackKey, activeIndex),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _deck(
    List<AppSection> sections,
    Key key,
    int activeIndex,
  ) {
    return PageStack(
      key: key,
      index: activeIndex,
      pages: pagesForSections(sections),
    );
  }

  int _indexOf(List<AppSection> sections, AppSection section) {
    final index = sections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  AppSection get _rootSection {
    final sections = _sections;
    if (sections.contains(AppSection.home)) return AppSection.home;
    return sections.isEmpty ? AppSection.home : sections.first;
  }

  /// 系统返回键：不在首页时先回首页，再按才退出应用。
  Future<bool> _handleWillPop() async {
    if (_active == _rootSection) return false;
    _select(_rootSection);
    return true;
  }
}
