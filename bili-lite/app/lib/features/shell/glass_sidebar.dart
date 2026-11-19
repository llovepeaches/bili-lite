import 'package:flutter/material.dart';

import '../../core/nav_section.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';

/// 宽屏扁平侧栏。
///
/// 保留原有类名与构造参数，但不再使用玻璃面板、透镜选中块、
/// 高光或半透明叠层：侧栏是实色卡片，选中项是浅粉圆角实底。
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
    final Color text = context.primaryTextColor;
    final Color sub = context.subTextColor;
    final Color line =
        context.isDark ? AppColors.darkLine : AppColors.lightLine;
    final int activeIndex = sections.indexOf(active);
    final int selectionIndex = activeIndex < 0 ? 0 : activeIndex;
    final double navHeight = _railItemHeight * sections.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
      child: SizedBox(
        width: extended ? 210 : 78,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: line),
          ),
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
                                color: text,
                              )),
                          Text('简洁 · 第三方',
                              style: TextStyle(fontSize: 10, color: sub)),
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
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      top: selectionIndex * _railItemHeight + 3,
                      left: extended ? 4 : 0,
                      width: extended ? 56 : 44,
                      height: 44,
                      child: const _SidebarSelectionBlock(),
                    ),
                    ...List<Widget>.generate(sections.length, (int i) {
                      final AppSection section = sections[i];
                      final bool selected = section == active;
                      return Positioned(
                        top: i * _railItemHeight,
                        left: 0,
                        right: 0,
                        height: _railItemHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
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
                                    color: selected ? text : sub,
                                  ),
                                ),
                              ),
                              if (extended) ...<Widget>[
                                const SizedBox(width: 14),
                                Text(
                                  section.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected ? text : sub,
                                  ),
                                ),
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
                  builder: (_, __) => GlassPill(
                    radius: 12,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSelectionBlock extends StatelessWidget {
  const _SidebarSelectionBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF50313B) : AppColors.pinkSoft,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

const double _railItemHeight = 52.0;
