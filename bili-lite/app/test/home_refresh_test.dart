import 'package:bililite/data/api_client.dart';
import 'package:bililite/data/models.dart';
import 'package:bililite/data/repository.dart';
import 'package:bililite/features/home/home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录每次请求参数的假仓库。
class _FakeRepo extends BiliRepository {
  _FakeRepo() : super(client: ApiClient.instance);

  final List<Map<String, dynamic>> feedCalls = <Map<String, dynamic>>[];

  @override
  Future<ApiResponse<List<Video>>> feed({
    int ps = 20,
    int freshIdx = 1,
    bool skipCache = false,
  }) async {
    feedCalls.add(<String, dynamic>{
      'ps': ps,
      'freshIdx': freshIdx,
      'skipCache': skipCache,
    });
    return ApiResponse<List<Video>>(
      data: <Video>[
        Video(bvid: 'BV$freshIdx', title: '第 $freshIdx 批'),
      ],
      source: 'live',
    );
  }
}

void main() {
  group('首页刷新', () {
    test('换一批会递增 fresh_idx 并强制绕过缓存', () async {
      final repo = _FakeRepo();
      final controller = HomeController(repository: repo);

      await controller.load(HomeChannel.recommended);
      expect(repo.feedCalls.length, 1);
      expect(repo.feedCalls[0]['freshIdx'], 1);
      expect(repo.feedCalls[0]['skipCache'], false);

      await controller.load(HomeChannel.recommended, force: true);
      expect(repo.feedCalls.length, 2);
      // 关键：fresh_idx 必须递增。
      // B 站的 fresh_idx 就是「换一批」游标，重置回 1 会拿到完全相同的一批。
      expect(repo.feedCalls[1]['freshIdx'], 2);
      // 同时必须绕过服务端 60 秒缓存，否则拿到的还是同一批。
      expect(repo.feedCalls[1]['skipCache'], true);

      await controller.load(HomeChannel.recommended, force: true);
      expect(repo.feedCalls[2]['freshIdx'], 3);

      controller.dispose();
    });

    test('换一批之后内容确实换了', () async {
      final repo = _FakeRepo();
      final controller = HomeController(repository: repo);
      await controller.load(HomeChannel.recommended);
      expect(controller.videosOf(HomeChannel.recommended).first.bvid, 'BV1');
      await controller.load(HomeChannel.recommended, force: true);
      expect(controller.videosOf(HomeChannel.recommended).first.bvid, 'BV2');
      controller.dispose();
    });

    test('已有内容时普通 load 不会重复请求', () async {
      final repo = _FakeRepo();
      final controller = HomeController(repository: repo);
      await controller.load(HomeChannel.recommended);
      await controller.load(HomeChannel.recommended);
      expect(repo.feedCalls.length, 1);
      controller.dispose();
    });
  });
}
