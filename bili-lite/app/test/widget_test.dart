import 'package:flutter_test/flutter_test.dart';

import 'package:bililite/core/format.dart';
import 'package:bililite/data/models.dart';

void main() {
  group('格式化', () {
    test('数字缩写', () {
      expect(Fmt.compact(0), '0');
      expect(Fmt.compact(9999), '9999');
      expect(Fmt.compact(12345), '1.2万');
      expect(Fmt.compact(123456789), '1.2亿');
    });

    test('时长', () {
      expect(Fmt.duration(0), '00:00');
      expect(Fmt.duration(74), '01:14');
      expect(Fmt.duration(3723), '1:02:03');
    });
  });

  group('数据模型', () {
    test('缺字段的 JSON 不会抛异常', () {
      final v = Video.fromJson(<String, dynamic>{'bvid': 'BV1test', 'title': '测试'});
      expect(v.bvid, 'BV1test');
      expect(v.stat.view, 0);
      expect(v.owner.name, '未知 UP 主');
      expect(v.webUrl, 'https://www.bilibili.com/video/BV1test');
    });

    test('序列化再反序列化保持一致', () {
      final v = Video.fromJson(<String, dynamic>{
        'aid': '123',
        'bvid': 'BV1abc',
        'title': '标题',
        'owner': <String, dynamic>{'mid': '9', 'name': 'UP'},
        'stat': <String, dynamic>{'view': 42, 'danmaku': 3},
      });
      final restored = Video.fromJson(v.toJson());
      expect(restored.title, '标题');
      expect(restored.stat.view, 42);
      expect(restored.owner.name, 'UP');
    });
  });
}
