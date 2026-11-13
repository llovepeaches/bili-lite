import 'package:flutter/material.dart';

import '../core/partitions.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import 'glass.dart';

/// 分区浮层选择器。
///
/// 改造前 21 个分区只能在排行榜频道的横向滚动条里选，条子挤在一行、
/// 名字一多就点不准。MiniBili 的做法是点「分区」弹出一个「图标 + 名称」
/// 的浮层网格，一眼能扫完 —— 这里照此实现。
///
/// 浮层用毛玻璃面板，与全局的液态玻璃语言保持一致，而不是系统默认的
/// Material 底部弹窗。
Future<void> showPartitionPicker(
  BuildContext context, {
  required int selectedRid,
  required ValueChanged<int> onSelected,
}) async {
  final partitions = BiliPartitions.items;
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.34),
    builder: (context) {
      final maxHeight = MediaQuery.of(context).size.height * 0.68;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          // 浮层是「盖在内容之上」的一层，玻璃太透会让下方的卡片文字与
          // 浮层文字叠在一起，读不清。这里在玻璃底下压一层接近不透明的
          // 实色底板，保证可读性，同时保留边缘的折射与高光。
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sheet + 4),
              color: context.isDark
                  ? const Color(0xF01A1F30)
                  : const Color(0xF7FFFFFF),
            ),
            child: GlassPanel(
              radius: AppRadius.sheet + 4,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const GlassAccent(),
                      const SizedBox(width: 8),
                      const Text(
                        '选择分区',
                        style:
                            TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '${partitions.length} 个分区',
                        style: TextStyle(fontSize: 11, color: context.subTextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 用 Wrap 而不是 GridView：GridView 在 Flexible 里会被撑到
                  // 剩余高度，行距被拉得很大；Wrap 按内容高度自适应。
                  // 外层再套一层可滚动，小屏（21 个分区放不下）时可滑动。
                  Flexible(
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const double spacing = 10;
                          const int columns = 4;
                          final double tileWidth =
                              (constraints.maxWidth - spacing * (columns - 1)) /
                                  columns;
                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: <Widget>[
                              for (final p in partitions)
                                SizedBox(
                                  width: tileWidth,
                                  child: _PartitionTile(
                                    partition: p,
                                    selected: p.rid == selectedRid,
                                    onTap: () => Navigator.of(context).pop(p.rid),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  if (picked != null) onSelected(picked);
}

/// 浮层里的单个分区格子：圆形图标 + 名称。
class _PartitionTile extends StatelessWidget {
  const _PartitionTile({
    required this.partition,
    required this.selected,
    required this.onTap,
  });

  final Partition partition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    final accent = BiliPartitions.colorOf(partition.rid);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? accent.withOpacity(0.18)
                  : (context.isDark
                      ? Colors.white.withOpacity(0.07)
                      : Colors.black.withOpacity(0.05)),
              border: Border.all(
                color: selected ? accent.withOpacity(0.55) : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Icon(
              BiliPartitions.iconOf(partition.rid),
              size: 20,
              color: selected ? accent : sub,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            partition.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : sub,
            ),
          ),
        ],
      ),
    );
  }
}
