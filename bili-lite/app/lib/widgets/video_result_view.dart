import 'package:flutter/material.dart';

import '../core/card_style.dart';
import '../core/responsive.dart';
import '../data/models.dart';
import 'state_views.dart';
import 'video_grid.dart';

/// 视频结果区的统一状态编排。
///
/// 首页 / 搜索 / 我的页过去各自重复同一组分支：
/// 首屏加载 → 骨架，错误且无数据 → 错误页，其余 → 网格。
/// 这里只做结构性抽取，分支顺序与参数保持原样，不改变视觉表现。
class VideoResultView extends StatelessWidget {
  const VideoResultView({
    Key? key,
    required this.videos,
    required this.onRefresh,
    required this.onTap,
    this.loading = false,
    this.error,
    this.ranked = false,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
    this.onRetry,
    this.header,
    this.empty,
    this.onLongPress,
    this.style = CardStyle.immersive,
  }) : super(key: key);

  final List<Video> videos;
  final Future<void> Function() onRefresh;
  final void Function(Video video) onTap;

  final bool loading;
  final String? error;
  final bool ranked;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRetry;
  final Widget? header;
  final Widget? empty;
  final void Function(Video video)? onLongPress;
  final CardStyle style;

  @override
  Widget build(BuildContext context) {
    if (loading && videos.isEmpty && error == null) {
      return LayoutBuilder(builder: (context, constraints) {
        return LoadingGrid(
          columns: Breakpoints.columns(constraints.maxWidth),
          style: style,
        );
      });
    }
    if (error != null && videos.isEmpty) {
      return ErrorView(
        message: error!,
        onRetry: onRetry ?? onRefresh,
      );
    }

    return VideoGrid(
      videos: videos,
      ranked: ranked,
      hasMore: hasMore,
      loadingMore: loadingMore,
      onLoadMore: onLoadMore,
      onRefresh: onRefresh,
      onTap: onTap,
      header: header,
      empty: empty,
      onLongPress: onLongPress,
      style: style,
    );
  }
}
