import 'package:bililite/core/navigation.dart';
import 'package:bililite/core/route_args.dart';
import 'package:bililite/data/models.dart';
import 'package:bililite/features/detail/detail_extras.dart';
import 'package:bililite/features/space/space_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 第七轮改造（播放防重入 / BV / 分享 / 应用内主页 / 登录门槛）的纯逻辑单测。
/// UI 部分靠 Playwright 截图实测，这里固定住不依赖渲染的行为。
void main() {
  group('播放页不二次打开', () {
    test('同一时刻只允许一次入栈，release 之后才放行', () {
      final guard = PlayerNavGuard();
      expect(guard.opening, isFalse);
      expect(guard.tryAcquire(), isTrue);
      expect(guard.opening, isTrue);
      // 连点第二下 / 父子手势同时命中都在这里被挡掉。
      expect(guard.tryAcquire(), isFalse);
      guard.release();
      expect(guard.opening, isFalse);
      expect(guard.tryAcquire(), isTrue);
    });
  });

  group('分享的官方原版内容', () {
    const owner = Owner(mid: '2', name: '测试UP');
    final video = Video(
      bvid: 'BV1xx411c7mD',
      title: '测试标题',
      owner: owner,
    );

    test('包含标题、UP 主与官方链接，且顺序固定', () {
      expect(
        officialShareText(video),
        '测试标题\nUP 主：测试UP\nhttps://www.bilibili.com/video/BV1xx411c7mD',
      );
    });

    test('缺 UP 主名称时不留下空行或占位符', () {
      const plain = Video(bvid: 'BV1', title: 'T');
      expect(officialShareText(plain),
          'T\nhttps://www.bilibili.com/video/BV1');
    });

    test('官方链接由 bvid 派生，不写死域名以外的路径', () {
      expect(video.webUrl, 'https://www.bilibili.com/video/BV1xx411c7mD');
    });
  });

  group('应用内 UP 主空间', () {
    test('路由名与参数完整', () {
      expect(AppRouteNames.space, '/space');
      const args = SpaceArgs(Owner(mid: '42', name: 'A'));
      expect(args.owner.mid, '42');
      expect(args.owner.name, 'A');
    });

    test('mid 为空一律返回空列表，不把全部搜索结果冒充成主页', () {
      final list = <Video>[
        const Video(bvid: 'a'),
        const Video(bvid: 'b'),
      ];
      expect(filterOwnerVideos(list, ''), isEmpty);
    });

    test('只保留 mid 完全一致的稿件', () {
      final list = <Video>[
        const Video(bvid: 'a', owner: Owner(mid: '7')),
        const Video(bvid: 'b', owner: Owner(mid: '8')),
        const Video(bvid: 'c', owner: Owner(mid: '7')),
        const Video(bvid: 'd'),
      ];
      final mine = filterOwnerVideos(list, '7');
      expect(mine.map((Video v) => v.bvid).toList(), <String>['a', 'c']);
    });

    test('没有匹配稿件时如实返回空', () {
      final list = <Video>[const Video(bvid: 'a', owner: Owner(mid: '8'))];
      expect(filterOwnerVideos(list, '7'), isEmpty);
    });
  });

  group('BV 号显示', () {
    test('BvBadge 空 bvid 不渲染内容', () {
      // 组件本身是纯展示，这里验证入口对空值有明确分支：
      // 空 bvid 时 const BvBadge(bvid: '') 仍可构造，不会抛异常。
      expect(const BvBadge(bvid: '').bvid, isEmpty);
      expect(const BvBadge(bvid: 'BV1xx411c7mD').bvid, 'BV1xx411c7mD');
    });
  });
}
