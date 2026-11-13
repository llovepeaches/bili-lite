import 'package:bililite/core/api_paths.dart';
import 'package:bililite/core/config.dart';
import 'package:bililite/core/partitions.dart';
import 'package:bililite/core/storage.dart';
import 'package:bililite/core/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('分区表单一数据源', () {
    test('21 项且 rid 唯一', () {
      expect(BiliPartitions.items.length, 21);
      final rids = BiliPartitions.items.map((e) => e.rid).toSet();
      expect(rids.length, BiliPartitions.items.length);
    });

    test('nameOf 能按 rid 查名，未知 rid 回落到通用名', () {
      expect(BiliPartitions.nameOf(0), '全站');
      expect(BiliPartitions.nameOf(168), '国创');
      expect(BiliPartitions.nameOf(999999), '分区');
    });

    test('首尾项与服务端 BFF 保持一致', () {
      // 服务端 server/src/index.js 的 PARTITIONS 同序同项，
      // 若客户端增删分区，服务端也必须同步，否则 meta 接口会返回不同结果。
      expect(BiliPartitions.items.first.rid, 0);
      expect(BiliPartitions.items.first.name, '全站');
      expect(BiliPartitions.items.last.rid, 11);
      expect(BiliPartitions.items.last.name, '电视剧');
    });
  });

  group('接口路径表不再是死代码', () {
    test('endpoints 与具名常量一致', () {
      expect(ApiConfig.endpoint('health'), ApiConfig.apiHealth);
      expect(ApiConfig.endpoint('feed'), ApiConfig.apiFeed);
      expect(ApiConfig.endpoint('rank'), ApiConfig.apiRank);
      expect(ApiConfig.endpoint('search'), ApiConfig.apiSearch);
      expect(ApiConfig.endpoint('video'), ApiConfig.apiVideo);
      expect(ApiConfig.endpoint('reply'), ApiConfig.apiReply);
    });

    test('未知 key 返回空串而不抛异常', () {
      expect(ApiConfig.endpoint('nope'), '');
    });

    test('ApiPaths 与 ApiConfig 转发完全一致', () {
      expect(ApiConfig.apiFeed, ApiPaths.feed);
      expect(ApiConfig.apiVideo, ApiPaths.video);
      expect(ApiConfig.endpoints, ApiPaths.endpoints);
      expect(ApiConfig.endpoint('reply'), ApiPaths.reply);
    });
  });

  group('本地存储门面', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('读写往返一致', () async {
      final store = LocalStore.instance;
      await store.init();
      expect(store.persistent, isTrue);

      await store.setString('k', 'v');
      await store.setInt('i', 42);
      await store.setBool('b', true);
      await store.setDouble('d', 1.5);
      await store.setStringList('l', <String>['a', 'b']);

      expect(store.getString('k'), 'v');
      expect(store.getInt('i'), 42);
      expect(store.getBool('b'), isTrue);
      expect(store.getDouble('d'), 1.5);
      expect(store.getStringList('l'), <String>['a', 'b']);
    });

    test('remove 后读回为 null', () async {
      final store = LocalStore.instance;
      await store.init();
      await store.setString('gone', 'x');
      await store.remove('gone');
      expect(store.getString('gone'), isNull);
    });

    test('JSON 列表读写往返，损坏数据按空列表处理', () async {
      final store = LocalStore.instance;
      await store.init();
      await store.setStringListAsJson('hist', <String>['猫', '狗']);
      expect(store.getStringListFromJson('hist'), <String>['猫', '狗']);

      await store.setString('hist', '{不是合法 JSON');
      expect(store.getStringListFromJson('hist'), isEmpty);

      await store.setString('hist', '{"不是":"数组"}');
      expect(store.getStringListFromJson('hist'), isEmpty);
    });

    test('不存在的 key 读为 null 而不是抛异常', () async {
      final store = LocalStore.instance;
      await store.init();
      expect(store.getString('__missing__'), isNull);
      expect(store.getInt('__missing__'), isNull);
      expect(store.getBool('__missing__'), isNull);
      expect(store.getStringListFromJson('__missing__'), isEmpty);
    });
  });

  group('设计令牌', () {
    test('状态色互不相同', () {
      final all = <Color>[
        AppStatus.success,
        AppStatus.warning,
        AppStatus.danger,
        AppStatus.neutral,
      ];
      expect(all.toSet().length, 4);
    });

    test('字号阶梯严格递增', () {
      final sizes = <double>[
        AppFontSize.micro,
        AppFontSize.caption,
        AppFontSize.small,
        AppFontSize.body,
        AppFontSize.bodyLarge,
        AppFontSize.title,
        AppFontSize.headline,
        AppFontSize.appBar,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]));
      }
    });

    test('圆角与间距层级不倒挂', () {
      expect(AppRadius.chip, lessThan(AppRadius.control));
      expect(AppRadius.control, lessThan(AppRadius.panel));
      expect(AppRadius.panel, lessThan(AppRadius.sheet));
      expect(AppRadius.sheet, lessThan(AppRadius.dock));
      expect(AppSpacing.xs, lessThan(AppSpacing.sm));
      expect(AppSpacing.sm, lessThan(AppSpacing.md));
      expect(AppSpacing.md, lessThan(AppSpacing.lg));
      expect(AppSpacing.lg, lessThan(AppSpacing.xl));
    });
  });
}
