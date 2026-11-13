import 'package:flutter/material.dart';

import '../data/models.dart';
import '../features/detail/detail_page.dart';
import '../state/globals.dart';
import '../state/library_state.dart';
import '../core/tokens.dart';

/// 打开视频详情页。
///
/// 重构前首页、搜索页、我的页各写了一份完全相同的
/// 「`library.addHistory(video)` → `Navigator.push(VideoDetailPage)`」，
/// 漏掉任何一处都会让观看历史不完整。现在收敛成一个入口。
///
/// 记录历史放在这里而不是各页面，是因为「打开详情」就意味着「看过」，
/// 这个因果关系属于导航行为本身。
Future<void> openVideoDetail(BuildContext context, Video video) async {
  await library.addHistory(video);
  final navigator = Navigator.of(context);
  // Flutter 3.0 没有 BuildContext.mounted；用 NavigatorState.mounted 判断，
  // 避免在页面已销毁时 push 导致崩溃。
  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => VideoDetailPage(video: video)),
  );
}

/// 切换某个本地列表的收藏状态并给出反馈。
///
/// 详情页与列表页都要用「收藏 / 稍后再看」，原先两处的提示文案与图标切换
/// 各写一遍。现在统一。
Future<void> toggleLibraryItem(
  BuildContext context,
  LibraryKind kind,
  Video video,
) async {
  final wasPresent = library.has(kind, video.bvid);
  await library.toggle(kind, video);
  final navigator = Navigator.of(context);
  if (!navigator.mounted) return;
  final label = kind == LibraryKind.favorites ? '收藏' : '稍后再看';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(wasPresent ? '已取消$label' : '已加入$label'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
  );
}
