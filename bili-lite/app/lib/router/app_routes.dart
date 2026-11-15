import 'package:flutter/material.dart';

import '../core/route_args.dart';
import '../features/detail/detail_view.dart';
import '../features/player/player_page.dart';
import '../features/space/space_view.dart';

/// 集中路由表。
///
/// 借鉴 PiliPlus 的 `lib/router/app_pages.dart`：所有可跳转页面在这里登记，
/// `MaterialApp.onGenerateRoute` 只认这一张表。新增页面时改这一个文件即可，
/// 不必再担心「某个地方忘了改路由」。
///
/// 参考实现用 GetX 的命名路由；本项目依赖极少，用 Flutter 原生的
/// `onGenerateRoute` + `Navigator.pushNamed` 达到同样效果，不引入额外依赖。
class AppRouter {
  AppRouter._();

  /// 交给 `MaterialApp.onGenerateRoute`。
  ///
  /// 参数类型不匹配时返回 null，由 Flutter 回退到「未知路由」处理，
  /// 而不是抛异常把整个导航栈带崩。
  static Route<dynamic>? generate(RouteSettings settings) {
    switch (settings.name) {
      case AppRouteNames.videoDetail:
        final args = settings.arguments;
        if (args is VideoDetailArgs) {
          return _route(VideoDetailView(video: args.video), settings);
        }
        return null;
      case AppRouteNames.player:
        final args = settings.arguments;
        if (args is PlayerArgs) {
          return _route(PlayerPage(video: args.video, page: args.page), settings);
        }
        return null;
      case AppRouteNames.space:
        final args = settings.arguments;
        if (args is SpaceArgs) {
          return _route(SpaceView(owner: args.owner), settings);
        }
        return null;
      default:
        return null;
    }
  }

  static MaterialPageRoute<T> _route<T>(Widget page, RouteSettings settings) {
    return MaterialPageRoute<T>(
      builder: (_) => page,
      settings: settings,
    );
  }
}
