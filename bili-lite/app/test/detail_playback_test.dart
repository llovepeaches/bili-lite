import 'package:bililite/core/route_args.dart';
import 'package:bililite/data/api_client.dart';
import 'package:bililite/data/models.dart';
import 'package:bililite/data/repository.dart';
import 'package:bililite/features/detail/detail_player.dart';
import 'package:bililite/features/detail/detail_view.dart';
import 'package:bililite/features/player/player_sections.dart';
import 'package:bililite/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 详情页内嵌播放回归。
///
/// 用户要求「视频详情不用二次打开页面播放」：点封面应在详情页原地起播，
/// 不再 push 独立播放页。这里用假仓库避免真实网络 / 视频插件，
/// 只固定「不 push、原地出现播放器、起播幂等」三个行为。
class _FakeRepo extends BiliRepository {
  _FakeRepo() : super(client: ApiClient.instance);

  @override
  Future<ApiResponse<VideoDetail>> video(String bvid, {String aid = ''}) async {
    return ApiResponse<VideoDetail>(
      data: VideoDetail(video: Video(bvid: bvid, aid: aid)),
      source: 'test',
    );
  }

  @override
  Future<ApiResponse<CommentPage>> reply(
    String aid, {
    int pn = 1,
    int ps = 20,
    int sort = 2,
  }) async {
    return ApiResponse<CommentPage>(data: const CommentPage(), source: 'test');
  }

  // 返回空播放地址：PlayerController 会标记「上游未返回可播放地址」，
  // 但不会调用底层视频插件，测试环境里安全。
  @override
  Future<ApiResponse<PlayUrl>> playUrl(
    String bvid,
    String cid, {
    int qn = 64,
  }) async {
    return ApiResponse<PlayUrl>(data: const PlayUrl(), source: 'test');
  }

  @override
  Future<ApiResponse<DanmakuList>> danmaku(String cid) async {
    return ApiResponse<DanmakuList>(data: const DanmakuList(), source: 'test');
  }
}

class FakeNavObserver extends NavigatorObserver {
  final List<String> pushed = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name ?? '(unnamed)');
    super.didPush(route, previousRoute);
  }
}

Widget _harness({
  required FakeNavObserver observer,
  required Video video,
  required BiliRepository repo,
}) {
  return MaterialApp(
    navigatorObservers: <NavigatorObserver>[observer],
    onGenerateRoute: AppRouter.generate,
    home: VideoDetailView(video: video, repository: repo),
  );
}

void main() {
  const video = Video(
    bvid: 'BV1xx411c7mD',
    aid: '123',
    cid: '456',
    title: '内嵌播放测试视频',
    cover: '',
  );

  testWidgets('点封面在详情页原地起播，不 push 独立播放页', (tester) async {
    final observer = FakeNavObserver();
    await tester.pumpWidget(_harness(
      observer: observer,
      video: video,
      repo: _FakeRepo(),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(DetailPlayer), findsNothing);

    // 点封面 GestureDetector 中心（播放圆按钮只是 IgnorePointer 装饰）。
    await tester.tap(find.byKey(const Key('detail-cover-play')));
    await tester.pump(const Duration(milliseconds: 200));

    // 关键：详情页内嵌播放器出现，且没有 push 播放路由。
    expect(find.byType(DetailPlayer), findsOneWidget);
    expect(find.byType(PlayerControls), findsWidgets);
    expect(observer.pushed, isNot(contains(AppRouteNames.player)));

    // 卸载页面，触发 DetailController.dispose 关闭弹幕定时器，
    // 避免 periodic Timer 泄漏到下一个测试。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });

  testWidgets('起播后 AppBar 的播放按钮再次点击不会 push / 不会重建播放器', (tester) async {
    final observer = FakeNavObserver();
    await tester.pumpWidget(_harness(
      observer: observer,
      video: video,
      repo: _FakeRepo(),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('detail-cover-play')));
    await tester.pump(const Duration(milliseconds: 200));

    final firstPlayer = tester.widget<DetailPlayer>(find.byType(DetailPlayer));

    // AppBar 工具组里的播放图标，起播后再点应幂等。
    final appBarPlay = find.byIcon(Icons.play_circle_outline_rounded);
    if (appBarPlay.evaluate().isNotEmpty) {
      await tester.tap(appBarPlay.first);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(DetailPlayer), findsOneWidget);
    expect(
      tester.widget<DetailPlayer>(find.byType(DetailPlayer)),
      same(firstPlayer),
    );
    expect(observer.pushed, isNot(contains(AppRouteNames.player)));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  });
}
