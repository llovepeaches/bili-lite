import 'package:flutter/material.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'video_card.dart';

/// 自适应网格：下拉刷新、触底加载更多、可选头部与排行榜名次。
/// 首页 / 排行榜 / 搜索结果 / 我的列表共用。
class VideoGrid extends StatelessWidget {
  const VideoGrid({
    Key? key,
    required this.videos,
    required this.onRefresh,
    required this.onTap,
    this.ranked = false,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
    this.header,
    this.controller,
    this.empty,
    this.onLongPress,
  }) : super(key: key);

  final List<Video> videos;
  final Future<void> Function() onRefresh;
  final void Function(Video video) onTap;
  final bool ranked;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onLoadMore;
  final Widget? header;
  final ScrollController? controller;
  final Widget? empty;
  final void Function(Video video)? onLongPress;

  /// 依据实际卡片宽度算宽高比：玻璃卡片有 8px 内边距，封面比卡片窄，
  /// 文字区高度基本固定。比写死 ratio 更紧凑，所有断点下都不会留白过大。
  double _aspect(double totalWidth, int columns, double gutter) {
    const double spacing = 14.0;
    const double inset = 8.0;
    const double textArea = 104.0; // 卡片上下内边距 + 标题两行 + UP 主 + 数据行
    final cardWidth =
        (totalWidth - gutter * 2 - spacing * (columns - 1)) / columns;
    final coverHeight = (cardWidth - inset * 2) * 9 / 16;
    return cardWidth / (coverHeight + textArea);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = Breakpoints.columns(width);
      final gutter = Breakpoints.gutter(width);

      return RefreshIndicator(
        color: AppColors.pink,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xF02A2C38)
            : const Color(0xFAFFFFFF),
        onRefresh: onRefresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (hasMore && !loadingMore && onLoadMore != null &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 400) {
              onLoadMore!();
            }
            return false;
          },
          child: CustomScrollView(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header!),
              if (videos.isEmpty && empty != null)
                SliverFillRemaining(hasScrollBody: false, child: empty!)
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 12,
                      childAspectRatio: _aspect(width, columns, gutter),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => VideoCard(
                        video: videos[index],
                        rank: ranked ? index + 1 : 0,
                        onTap: () => onTap(videos[index]),
                        onLongPress: onLongPress == null
                            ? null
                            : () => onLongPress!(videos[index]),
                      ),
                      childCount: videos.length,
                    ),
                  ),
                ),
              if (loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: hasMore ? 12 : 28),
              ),
            ],
          ),
        ),
      );
    });
  }
}
