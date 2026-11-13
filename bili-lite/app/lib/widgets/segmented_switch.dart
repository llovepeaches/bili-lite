import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import 'glass.dart';

/// 玻璃分段控件。
///
/// Flutter 3.0 还没有 Material 3 的 `SegmentedButton`（3.7 才引入），
/// 而 MiniBili 的详情页用「详情 / 评论」这样的分段切换。这里自绘一个，
/// 风格与全局的液态玻璃语言保持一致：外层是半透明胶囊容器，
/// 选中项是一枚带粉色调的玻璃胶囊。
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    Key? key,
    required this.labels,
    required this.index,
    required this.onChanged,
  }) : super(key: key);

  /// 分段文案。
  final List<String> labels;

  /// 当前选中下标。
  final int index;

  /// 选中项变化回调。
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: AppRadius.pill,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 34,
        child: Row(
          children: List<Widget>.generate(labels.length, (i) {
            final selected = i == index;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: selected
                        ? AppColors.pink.withOpacity(0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.pink.withOpacity(0.45)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.pink : sub,
                    ),
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
