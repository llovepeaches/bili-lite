import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'glass.dart';

/// 页面顶部的信息卡片：标题 + 计数 + 副标题 + 右侧操作。
///
/// 重构前首页（`_buildHeader`）、我的页、搜索页各自写了一遍
/// `GlassPanel(radius: 20, padding: fromLTRB(14,14,14,12))` + `Row(标题 + 计数
/// + Spacer + 操作)` + `副标题` 的结构，只有文案和操作按钮不同。
///
/// 现在统一成一个组件，页面只描述差异。
class PageHeaderCard extends StatelessWidget {
  const PageHeaderCard({
    Key? key,
    required this.title,
    this.subtitle,
    this.count,
    this.trailing,
    this.subtitleWidget,
  }) : super(key: key);

  /// 主标题，例如「为你推荐」。
  final String title;

  /// 副标题，说明当前内容来源。
  final String? subtitle;

  /// 计数文案，例如「共 20 条」。为空则不显示。
  final String? count;

  /// 右侧操作区，例如「清空」按钮。
  final Widget? trailing;

  /// 副标题下方的自定义内容，例如首页的分区切换条。
  final Widget? subtitleWidget;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md + 2, AppSpacing.lg, AppSpacing.xs),
      child: GlassPanel(
        radius: AppRadius.panel,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                if (count != null && count!.isNotEmpty) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  Text(count!,
                      style:
                          TextStyle(fontSize: AppFontSize.caption, color: sub)),
                ],
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!,
                  style: TextStyle(fontSize: AppFontSize.small, color: sub)),
            ],
            if (subtitleWidget != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              subtitleWidget!,
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
