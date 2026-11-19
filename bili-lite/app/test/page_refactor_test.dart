import 'package:bililite/data/api_client.dart';
import 'package:bililite/data/models.dart';
import 'package:bililite/data/repository.dart';
import 'package:bililite/features/space/space_controller.dart';
import 'package:bililite/widgets/state_views.dart';
import 'package:bililite/widgets/video_grid.dart';
import 'package:bililite/widgets/video_result_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpaceRepo extends BiliRepository {
  _SpaceRepo() : super(client: ApiClient.instance);

  @override
  Future<ApiResponse<SearchResult>> search(String keyword,
      {int page = 1}) async {
    return ApiResponse<SearchResult>(
      data: SearchResult(
        list: <Video>[
          const Video(bvid: 'a', owner: Owner(mid: '7')),
          const Video(bvid: 'b', owner: Owner(mid: '8')),
          const Video(bvid: 'c', owner: Owner(mid: '7')),
        ],
      ),
      source: 'test',
    );
  }
}

void main() {
  group('统一视频结果区', () {
    testWidgets('首屏加载时只显示骨架', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VideoResultView(
          videos: const <Video>[],
          loading: true,
          onRefresh: () async {},
          onTap: (_) {},
        ),
      ));

      expect(find.byType(LoadingGrid), findsOneWidget);
      expect(find.byType(VideoGrid), findsNothing);
    });

    testWidgets('错误态点击重试会走统一刷新入口', (tester) async {
      int retried = 0;
      await tester.pumpWidget(MaterialApp(
        home: VideoResultView(
          videos: const <Video>[],
          error: '服务没连上',
          onRefresh: () async {
            retried++;
          },
          onTap: (_) {},
        ),
      ));

      expect(find.byType(ErrorView), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('有数据时保留头部与网格，空态不渲染', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VideoResultView(
          videos: const <Video>[Video(bvid: 'BV1', title: '测试视频')],
          header: const Text('结果头'),
          empty: const Text('空态'),
          onRefresh: () async {},
          onTap: (_) {},
        ),
      ));

      expect(find.byType(VideoGrid), findsOneWidget);
      expect(find.text('结果头'), findsOneWidget);
      expect(find.text('空态'), findsNothing);
    });
  });

  group('UP 主空间控制器', () {
    test('按 mid 过滤搜索结果并通知视图刷新', () async {
      final controller = SpaceController(
        owner: const Owner(mid: '7', name: '测试UP'),
        repository: _SpaceRepo(),
      );
      int notifications = 0;
      controller.addListener(() => notifications++);

      await controller.load();

      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
      expect(
        controller.videos.map((v) => v.bvid).toList(),
        <String>['a', 'c'],
      );
      expect(notifications, greaterThanOrEqualTo(2));
      controller.dispose();
    });
  });
}
