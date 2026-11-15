import '../data/models.dart';

/// 路由名与路由参数。
///
/// 重构前所有页面跳转都是裸的 `Navigator.push(MaterialPageRoute(...))`，
/// 散落在 home / search / library / detail / player 五处，既没有集中清单，
/// 也没法统一做转场或埋点。这里把「叫什么名字、带什么参数」抽成纯数据，
/// 放在 core 里是为了让它不依赖任何 UI 模块，避免 router ↔ features 循环引用。
class AppRouteNames {
  AppRouteNames._();

  static const String videoDetail = '/video-detail';
  static const String player = '/player';
  static const String space = '/space';
}

/// 视频详情页参数。
class VideoDetailArgs {
  const VideoDetailArgs(this.video);

  final Video video;
}

/// 应用内播放器参数。
class PlayerArgs {
  const PlayerArgs(this.video, {this.page = 1});

  final Video video;

  /// 分 P 序号，从 1 开始。
  final int page;
}

/// 应用内 UP 主空间参数。
///
/// 「查看主页」原先直接跳系统浏览器，现在改成 push 这个命名路由，在应用内
/// 展示 UP 主资料与其稿件，不再离开 App。
class SpaceArgs {
  const SpaceArgs(this.owner);

  final Owner owner;
}
