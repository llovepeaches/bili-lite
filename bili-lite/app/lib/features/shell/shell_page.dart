import 'package:flutter/material.dart';

import '../../core/nav_section.dart';
import '../../core/responsive.dart';
import '../../state/globals.dart';
import '../../widgets/liquid_dock.dart';
import 'dock_compact_policy.dart';
import 'glass_sidebar.dart';
import 'shell_page_factory.dart';
import 'swipe_deck.dart';

/// 导航壳：窄屏悬浮液态玻璃 dock，宽屏悬浮玻璃侧栏。
///
/// 内容区用 [SwipeDeck] 承载：左右滑动时**只有内容页面跟手平移**，
/// 底栏固定不动，只通过选中项（液态透镜）的位置与颜色变化指示当前页面。
/// 页面切换手势走 [SwipeDeck]，内部小控件（分区横条、Slider）仍优先拿到手势。
///
/// 导航项不再写死：来自 `AppPrefs.sections`，用户可以在设置里增删与排序
/// （参考 PiliPlus 的 `NavBarConfig`）。这里用 [AppSection] 而不是下标来
/// 记录当前选中项 —— 顺序变了之后按下标记忆会选错页面。
///
/// 页面装配在 `shell_page_factory.dart`，宽屏侧栏在 `glass_sidebar.dart`；
/// 本文件只负责壳状态、手势分发与窄 / 宽屏布局编排。
class ShellPage extends StatefulWidget {
  const ShellPage({Key? key}) : super(key: key);

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  AppSection? _current;

  /// 拖动过程中底栏透镜预览到的下标；与 [_active] 分离，
  /// 这样「高光跟手移动」和「真正切到了哪一页」是两件事。
  int? _previewIndex;

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

  /// 底栏高光当前停在哪个入口：拖动预览优先，否则用已提交的页面。
  AppSection get _dockSection {
    final preview = _previewIndex;
    if (preview != null && preview >= 0 && preview < _sections.length) {
      return _sections[preview];
    }
    return _active;
  }

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
        final preview = _previewIndex;
        if (preview != null && preview >= sections.length) {
          _previewIndex = null;
        }

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
                          active: _dockSection,
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
                    // 宽屏侧栏与窄屏底栏共用同一份"预览下标"，
                    // 拖动过程中高光跟手移动，两端表现一致。
                    active: _dockSection,
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
    return SwipeDeck(
      key: key,
      index: activeIndex,
      pages: pagesForSections(sections),
      onIndexChanged: (index) {
        if (index < 0 || index >= sections.length) return;
        if (_current == sections[index]) {
          setState(() => _previewIndex = null);
          return;
        }
        setState(() {
          _current = sections[index];
          _previewIndex = null;
        });
      },
      onIndexPreview: (index) {
        if (index < 0 || index >= sections.length) return;
        if (_previewIndex == index) return;
        setState(() => _previewIndex = index);
      },
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
