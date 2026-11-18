import 'package:flutter/material.dart';

import '../../core/glass_theme.dart';
import 'dock_compact_policy.dart';
import '../../core/nav_section.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';
import '../../widgets/liquid_dock.dart';
import '../home/home_view.dart';
import '../library/library_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';
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
  ///
  /// 底栏是双件式结构（胶囊 + 右侧独立圆形按钮），滑动的页序必须
  /// 跟视觉顺序一致 —— 搜索在屏幕最右，往左滑才会从「设置」进到「搜索」。
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
    // 内容区跟着滑过去（SwipeDeck 受控于 [_active]），底栏只更新选中态。
  }

  /// 内容区滚动时，底栏跟随收起 / 展开。
  ///
  /// 对齐 iOS 26 的 `.tabBarMinimizeBehavior(.onScrollDown)`：
  /// 向下滚动内容时底栏收起成 compact（标签淡出、只留图标），
  /// 把屏幕空间还给内容；向上滚动时恢复。
  ///
  /// 注意这里和**横向**滑动切页是两件独立的事：
  /// `SwipeDeck` 用的是 `onHorizontalDrag*`，只在内容区生效，
  /// 底栏的收起只看竖直滚动方向，两者互不干扰。
  ///
  /// 为什么监听 [ScrollNotification] 而不是 [UserScrollNotification]：
  ///
  /// `UserScrollNotification` 只在**滚动方向发生变化**的那一刻派发一次
  /// （Flutter 的 `updateUserScrollDirection` 里 `if (userScrollDirection == value) return;`），
  /// 而且**鼠标滚轮**在 Linux 桌面上常常压根不派发它 ——
  /// 实测：滚轮事件确实到达（`PointerScrollEvent.scrollDelta.dy = -53`），
  /// 但 `UserScrollNotification` 一条都没有。
  ///
  /// `ScrollUpdateNotification` 则**每次**滚动都派发，
  /// 且带 `scrollDelta`，用位移的正负就能判断方向 ——
  /// 滚轮、拖拽、惯性 fling 一视同仁。
  bool _onScroll(ScrollNotification notification) {
    // 判定逻辑在 [DockCompactPolicy] 里（纯函数，可单独测）。
    final bool? next = _compactPolicy.compactFor(notification);
    if (next == null) return false;
    _setCompact(next);
    return false;
  }

  /// 设置 compact 态；值没变就不重建。
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
        // 用户改了导航项顺序之后，用新的 key 重建内容容器，
        // 否则旧的子页面会按旧下标留在原位。
        final stackKey =
            ValueKey<String>(sections.map((e) => e.key).join(','));
        final activeIndex = _indexOf(sections, _active);
        // 导航项顺序变了以后，旧的预览下标已经指向另一个入口，清掉它。
        final preview = _previewIndex;
        if (preview != null && preview >= sections.length) {
          _previewIndex = null;
        }

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
                  body: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: _deck(sections, stackKey, activeIndex),
                  ),
                  bottomNavigationBar: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      // 底栏固定在 Scaffold 底部：内容区滑动时它只做
                      // 「收起 / 展开」的纵向收缩，选中态（水滴透镜的
                      // 位置与颜色）跟随变化。
                      //
                      // 双件式：左边胶囊装标签组，右边一枚独立圆形按钮装搜索。
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
                  _GlassSidebar(
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

  /// 内容区：跟手滑动的分页容器。
  ///
  /// 索引由 [_active] 单向控制：外部（底栏点击）改 [_active] → 内容区滑过去；
  /// 用户滑动 → 内容区吸附完成后回调 [SwipeDeck.onIndexChanged] → 改 [_active]。
  /// 拖动过程中只更新高光预览（[SwipeDeck.onIndexPreview]），不提交页面切换。
  Widget _deck(
    List<AppSection> sections,
    Key key,
    int activeIndex,
  ) {
    return SwipeDeck(
      key: key,
      index: activeIndex,
      pages: _pagesFor(sections),
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
          // 侧栏是大面积导航玻璃：走导航级采样，与底栏同一套光学参数。
          blur: GlassTheme.of(context).navBlur > 0
              ? GlassTheme.of(context).navBlur
              : null,
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
                    // 选中态用与窄屏底栏同一枚液态透镜（[LiquidLens]），
                    // 两种形态下的高光是同一套视觉语言。
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      top: sections.indexOf(active) * _railItemHeight + 3,
                      left: extended ? 6 : 0,
                      width: extended ? 40 : 44,
                      height: 44,
                      child: const LiquidLens(size: 44),
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
                              // 透镜宽 44，图标居中其中。
                              SizedBox(
                                width: 44,
                                child: Center(
                                  child: Icon(
                                    selected ? section.selectedIcon : section.icon,
                                    size: 21,
                                    color: selected ? AppColors.pink : sub,
                                  ),
                                ),
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

const double _railItemHeight = 52.0;
