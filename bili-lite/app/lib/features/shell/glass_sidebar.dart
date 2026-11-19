import 'package:flutter/material.dart';

import '../../core/glass_theme.dart';
import '../../core/nav_section.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';
import '../../widgets/liquid_dock.dart';

/// 宽屏悬浮玻璃侧栏，选中项背后有一枚会滑动的玻璃胶囊。
class GlassSidebar extends StatelessWidget {
  const GlassSidebar({
    Key? key,
    required this.sections,
    required this.active,
    required this.extended,
    required this.onSelect,
  }) : super(key: key);

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
                              SizedBox(
                                width: 44,
                                child: Center(
                                  child: Icon(
                                    selected
                                        ? section.selectedIcon
                                        : section.icon,
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
                                        color:
                                            selected ? AppColors.pink : sub)),
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
                    message:
                        '服务状态：${appState.serviceError.isEmpty ? '正常' : '未连接'}',
                    child: GlassPill(
                      radius: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 6),
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
