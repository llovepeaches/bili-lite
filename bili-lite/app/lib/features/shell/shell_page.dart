import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavItem> _navItems = <_NavItem>[
  _NavItem('首页', Icons.home_outlined, Icons.home_rounded),
  _NavItem('搜索', Icons.search_outlined, Icons.search_rounded),
  _NavItem('我的', Icons.bookmarks_outlined, Icons.bookmarks_rounded),
  _NavItem('设置', Icons.settings_outlined, Icons.settings_rounded),
];

const double _railItemHeight = 52.0;

/// 导航壳：窄屏悬浮玻璃 dock，宽屏悬浮玻璃侧栏，页面用 IndexedStack 保活。
class ShellPage extends StatefulWidget {
  const ShellPage({Key? key}) : super(key: key);

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  final List<Widget> _pages = const <Widget>[
    HomePage(),
    SearchPage(),
    LibraryPage(),
    SettingsPage(),
  ];

  void _select(int index) {
    if (_index != index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
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
          child: Scaffold(
            extendBody: true,
            body: IndexedStack(index: _index, children: _pages),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: _GlassDock(index: _index, onSelect: _select),
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
                index: _index,
                extended: extended,
                onSelect: _select,
              ),
              Expanded(child: IndexedStack(index: _index, children: _pages)),
            ],
          ),
        ),
      );
    });
  }
}

/// 宽屏：悬浮玻璃侧栏，选中项背后有一枚会滑动的玻璃胶囊。
class _GlassSidebar extends StatelessWidget {
  const _GlassSidebar({
    required this.index,
    required this.extended,
    required this.onSelect,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    const double navHeight = _railItemHeight * 4;

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
                    const _Logo(),
                    if (extended) ...<Widget>[                      const SizedBox(width: 10),
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
                      top: index * _railItemHeight + 3,
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
                    ...List<Widget>.generate(_navItems.length, (i) {
                      final item = _navItems[i];
                      final selected = i == index;
                      return Positioned(
                        top: i * _railItemHeight,
                        left: 0,
                        right: 0,
                        height: _railItemHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => onSelect(i),
                          child: Row(
                            mainAxisAlignment: extended
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: <Widget>[
                              if (extended) const SizedBox(width: 14),
                              Icon(
                                selected ? item.selectedIcon : item.icon,
                                size: 21,
                                color: selected ? AppColors.pink : sub,
                              ),
                              if (extended) ...<Widget>[
                                const SizedBox(width: 14),
                                Text(item.label,
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
  const _GlassDock({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;

    return LayoutBuilder(builder: (context, constraints) {
      final innerWidth = constraints.maxWidth - 12;
      final itemWidth = innerWidth / _navItems.length;
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
                left: index * itemWidth + 4,
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
                children: List<Widget>.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final selected = i == index;
                  return SizedBox(
                    width: itemWidth,
                    height: 56,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => onSelect(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            selected ? item.selectedIcon : item.icon,
                            size: 21,
                            color: selected ? AppColors.pink : sub,
                          ),
                          const SizedBox(height: 3),
                          Text(item.label,
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

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const AppLogo();
  }
}
