import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import 'glass.dart';

/// 扁平分段控件。
///
/// Flutter 3.0 还没有 Material 3 的 `SegmentedButton`（3.7 才引入），
/// 而详情页用「详情 / 评论」这样的分段切换。这里自绘一个：
/// 外层保持原有卡片骨架，选中项是浅粉圆角实底 + 勾选，
/// 未选中项是白底黑边，文字统一为黑色。
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    Key? key,
    required this.labels,
    required this.index,
    required this.onChanged,
  }) : super(key: key);

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color textColor = context.primaryTextColor;
    final Color lineColor = context.isDark ? AppColors.darkLine : textColor;

    return GlassPanel(
      radius: AppRadius.pill,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 34,
        child: Row(
          children: List<Widget>.generate(labels.length, (int i) {
            final bool selected = i == index;
            final Color background = selected
                ? (context.isDark
                    ? const Color(0xFF50313B)
                    : AppColors.pinkSoft)
                : AppColors.lightCard;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: background,
                    border: Border.all(
                      color: selected ? background : lineColor,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (selected) ...<Widget>[
                        Icon(Icons.check_rounded, size: 14, color: textColor),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: AppFontSize.body,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
