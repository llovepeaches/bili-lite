import 'package:flutter/material.dart';

import '../../core/nav_section.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';

/// 导航项配置编辑器：显示 / 隐藏 + 上下移动排序。
///
/// 借鉴 PiliPlus 的 `NavBarConfig`：导航项本身是一份可配置清单，用户能按
/// 自己的习惯排列入口，而不是被写死的一组标签。
///
/// 这也是「导航项被硬编码在 shell_page.dart」这个问题的正解 ——
/// 改动入口集合不需要再动壳层代码。
class NavConfigEditor extends StatelessWidget {
  const NavConfigEditor({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        final visible = prefs.sections;
        final hidden = AppSection.values
            .where((s) => !visible.contains(s))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < visible.length; i++)
              _NavRow(
                section: visible[i],
                index: i,
                total: visible.length,
              ),
            if (hidden.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('未显示的入口', style: TextStyle(fontSize: 11.5, color: sub)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: hidden
                    .map((s) => GlassChip(
                          label: s.label,
                          icon: s.icon,
                          radius: 11,
                          onTap: () => prefs.toggleSection(s),
                        ))
                    .toList(),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 单个导航项：图标 + 名称 + 排序 + 隐藏。
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.section,
    required this.index,
    required this.total,
  });

  final AppSection section;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(section.icon, size: 18, color: AppColors.pink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(section.label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          _IconAction(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: '上移',
            enabled: index > 0,
            onTap: () => prefs.moveSection(section, -1),
          ),
          _IconAction(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: '下移',
            enabled: index < total - 1,
            onTap: () => prefs.moveSection(section, 1),
          ),
          _IconAction(
            icon: Icons.visibility_outlined,
            tooltip: '隐藏',
            enabled: total > 1,
            onTap: () => prefs.toggleSection(section),
          ),
          const SizedBox(width: 2),
          Text('${index + 1}',
              style: TextStyle(fontSize: 10.5, color: sub)),
        ],
      ),
    );
  }
}

/// 排序 / 显隐用的小图标按钮。
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? sub : sub.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}
