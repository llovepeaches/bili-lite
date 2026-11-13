import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/nav_section.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';
import '../home/home_view.dart';
import '../library/library_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';

/// 导航壳：窄屏悬浮玻璃 dock，宽屏悬浮玻璃侧栏，页面用 IndexedStack 保活。
///
/// 导航项不再写死：来自 `AppPrefs.sections`，用户可以在设置里增删与排序
/// （参考 PiliPlus 的 `NavBarConfig`）。这里用 [AppSection] 而不是下标来
/// 记录当前选中项 —— 顺序变了之后按下标记忆会选错页面。
class ShellPage extends StatefulWidget {
  const ShellPage({Key? key}) : super(key: key);

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  AppSection? _current;

  /// 底部 dock 是否显示。向下滚动时收起，向上滚动时回来。
  bool _dockVisible = true;

  List<AppSection> get _sections => prefs.sections;

  AppSection get _active =>
      _current ?? (_sections.isEmpty ? AppSection.home : _sections.first);

  void _select(AppSection section) {
    if (_active == section) return;
    setState(() {
      _current = section;
      _dockVisible = true;
    });
  }

  /// 滚动方向驱动 dock 显隐。借鉴 PiliPlus 的 hideBottomBar：
  /// 内容很长时把 dock 收起，把整屏留给内容。
  bool _onScroll(UserScrollNotification notification) {
    if (!prefs.hideDockOnScroll) return false;
    final direction = notification.direction;
    if (direction == ScrollDirection.reverse && _dockVisible) {
      setState(() => _dockVisible = false);
    } else if (direction == ScrollDirection.forward && !_dockVisible) {
      setState(() => _dockVisible = true);
    }
    return false;
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
        // 用户改了导航项顺序之后，用新的 key 重建 IndexedStack，
        // 否则旧的子页面会按旧下标留在原位。
        final stackKey =
            ValueKey<String>(sections.map((e) => e.key).join(','));

        return LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (!Breakpoints.useRail(width)) {
            // 窄屏：内容延伸到 dock 之后（玻璃透出背景），但要把 dock 占用的高度
            // 告诉页面，否则列表最后一行会被盖住、点不到。
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
                  body: NotificationListener<UserScrollNotification>(
                    onNotification: _onScroll,
                    child: IndexedStack(
                      key: stackKey,
                      index: _indexOf(sections, _active),
                      children: _pagesFor(sections),
                    ),
                  ),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset:
                          _dockVisible ? Offset.zero : const Offset(0, 1.4),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: _GlassDock(
                          sections: sections,
                          active: _active,
                          onSelect: _select,
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
                  _GlassSidebar(
                    sections: sections,
                    active: _active,
                    extended: extended,
                    onSelect: _select,
                  ),
                  Expanded(
                    child: IndexedStack(
                      key: stackKey,
                      index: _indexOf(sections, _active),
                      children: _pagesFor(sections),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  int _indexOf(List<AppSection> sections, AppSection section) {
    final index = sections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  /// 返回键的目标页：优先首页；首页被用户隐藏时退回第一个入口。
  AppSection get _rootSection {
    final sections = _sections;
    if (sections.contains(AppSection.home)) return AppSection.home;
    return sections.isEmpty ? AppSection.home : sections.first;
  }

  /// 系统返回键：不在首页时先回首页，再按才退出应用。
  ///
  /// 借鉴 PiliPlus 的返回键处理 —— 底部有多个 tab 时，直接按返回把应用
  /// 关掉会让人措手不及，先回首页是更符合直觉的行为。
  Future<bool> _handleWillPop() async {
    if (_active == _rootSection) return false;
    _select(_rootSection);
    return true;
  }

  List<Widget> _pagesFor(List<AppSection> sections) {
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
}

/// 宽屏：悬浮玻璃侧栏，选中项背后有一枚会滑动的玻璃胶囊。
class _GlassSidebar extends StatelessWidget {
  const _GlassSidebar({
    required this.sections,
    required this.active,
    required this.extended,
    required this.onSelect,
  });

  final List<AppSection> sections;
  final AppSection active;
  final bool extended;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    final navHeight = _railItemHeight * sections.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
      child: SizedBox(
        width: extended ? 210 : 78,
        child: GlassPanel(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          // 导航层是 iOS 里最"活"的玻璃：订阅共享镜面时钟，亮斑沿轮廓流动。
          specular: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AppLogo(),
                    if (extended) ...<Widget>[
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('Bili Lite',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.primaryTextColor)),
                          Text('简洁 · 第三方',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.pink.withOpacity(0.95))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: navHeight,
                child: Stack(
                  children: <Widget>[
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      top: sections.indexOf(active) * _railItemHeight + 3,
                      left: 0,
                      right: 0,
                      height: _railItemHeight - 6,
                      child: GlassPanel(
                        radius: 999,
                        padding: EdgeInsets.zero,
                        tint: AppColors.pink,
                        child: const SizedBox.shrink(),
                      ),
                    ),
                    ...List<Widget>.generate(sections.length, (i) {
                      final section = sections[i];
                      final selected = section == active;
                      return Positioned(
                        top: i * _railItemHeight,
                        left: 0,
                        right: 0,
                        height: _railItemHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => onSelect(section),
                          child: Row(
                            mainAxisAlignment: extended
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: <Widget>[
                              if (extended) const SizedBox(width: 14),
                              Icon(
                                selected ? section.selectedIcon : section.icon,
                                size: 21,
                                color: selected ? AppColors.pink : sub,
                              ),
                              if (extended) ...<Widget>[
                                const SizedBox(width: 14),
                                Text(section.label,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected ? AppColors.pink : sub)),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: AnimatedBuilder(
                  animation: appState,
                  builder: (_, __) => Tooltip(
                    message: '服务状态：${appState.serviceError.isEmpty ? '正常' : '未连接'}',
                    child: GlassPill(
                      radius: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: appState.serviceError.isEmpty
                                  ? AppStatus.success
                                  : AppStatus.warning,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                    color: (appState.serviceError.isEmpty
                                            ? AppStatus.success
                                            : AppStatus.warning)
                                        .withOpacity(0.6),
                                    blurRadius: 6),
                              ],
                            ),
                          ),
                          if (extended) ...<Widget>[
                            const SizedBox(width: 7),
                            Text(
                              appState.serviceError.isEmpty ? '在线' : '离线',
                              style: TextStyle(fontSize: 10.5, color: sub),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 窄屏：悬浮玻璃 dock，半透明叠在内容之上，选中胶囊横向滑动。
class _GlassDock extends StatelessWidget {
  const _GlassDock({
    required this.sections,
    required this.active,
    required this.onSelect,
  });

  final List<AppSection> sections;
  final AppSection active;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;

    return LayoutBuilder(builder: (context, constraints) {
      final innerWidth = constraints.maxWidth - 12;
      final itemWidth = innerWidth / sections.length;
      return GlassPanel(
        radius: 26,
        padding: const EdgeInsets.all(6),
        specular: true,
        child: SizedBox(
          height: 56,
          child: Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                left: sections.indexOf(active) * itemWidth + 4,
                top: 3,
                width: itemWidth - 8,
                height: 50,
                child: GlassPanel(
                  radius: 999,
                  padding: EdgeInsets.zero,
                  tint: AppColors.pink,
                  child: const SizedBox.shrink(),
                ),
              ),
              Row(
                children: List<Widget>.generate(sections.length, (i) {
                  final section = sections[i];
                  final selected = section == active;
                  return SizedBox(
                    width: itemWidth,
                    height: 56,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => onSelect(section),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            selected ? section.selectedIcon : section.icon,
                            size: 21,
                            color: selected ? AppColors.pink : sub,
                          ),
                          const SizedBox(height: 3),
                          Text(section.label,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected ? AppColors.pink : sub)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      );
    });
  }
}

const double _railItemHeight = 52.0;
