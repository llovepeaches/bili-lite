import 'package:flutter/material.dart';

import '../core/route_args.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import '../state/globals.dart';
import '../state/library_state.dart';

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
  await navigator.pushNamed(
    AppRouteNames.videoDetail,
    arguments: VideoDetailArgs(video),
  );
}

/// 播放页入栈防重入。
///
/// 详情页封面和中央播放按钮曾经各绑了一次 `openPlayer`，快速点击（或父子
/// 手势同时命中）会把两个 PlayerPage 叠进导航栈，返回一次还停在播放页，
/// 看起来就是「播放视频要二次打开」。抽成可单测的门闩，保证一次点击
/// 只入栈一次，直到用户退出播放页才放行下一次。
class PlayerNavGuard {
  bool _opening = false;

  bool get opening => _opening;

  bool tryAcquire() {
    if (_opening) return false;
    _opening = true;
    return true;
  }

  void release() => _opening = false;
}

final PlayerNavGuard playerNavGuard = PlayerNavGuard();

/// 打开应用内播放页（保证一次点击只入栈一次）。
Future<void> openPlayer(BuildContext context, Video video, {int page = 1}) async {
  if (!playerNavGuard.tryAcquire()) return;
  final navigator = Navigator.of(context);
  if (!navigator.mounted) {
    // 拿不到 navigator 也必须放锁，否则后续所有播放入口会被永久挡住。
    playerNavGuard.release();
    return;
  }
  try {
    await navigator.pushNamed(
      AppRouteNames.player,
      arguments: PlayerArgs(video, page: page),
    );
  } finally {
    playerNavGuard.release();
  }
}

/// 在应用内打开 UP 主空间，不再跳系统浏览器。
Future<void> openSpace(BuildContext context, Owner owner) async {
  if (owner.mid.isEmpty) return;
  final navigator = Navigator.of(context);
  if (!navigator.mounted) return;
  await navigator.pushNamed(
    AppRouteNames.space,
    arguments: SpaceArgs(owner),
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
