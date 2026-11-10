// 联网冒烟：在 Dart VM 里直接跑原生端的数据链路，验证安装包不依赖
// 本机 Node BFF 也能拿到 B 站实时数据。
//
//   cd app && dart run tool/verify_live.dart
//
// 这是开发期自检脚本，不进 flutter test（后者应保持离线可跑）。

import 'dart:convert';

import '../lib/data/bili_direct.dart';

String _title(dynamic data) {
  if (data is List && data.isNotEmpty) {
    final first = data.first;
    if (first is Map) return (first['title'] ?? '').toString();
  }
  if (data is Map) {
    final list = data['list'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) return (first['title'] ?? '').toString();
    }
    return (data['title'] ?? '').toString();
  }
  return '';
}

int _count(dynamic data) {
  if (data is List) return data.length;
  if (data is Map) {
    final list = data['list'];
    if (list is List) return list.length;
    return 1;
  }
  return 0;
}

Future<void> main() async {
  final direct = BiliDirect.instance;
  final online = await direct.probe();
  print('探活        : ${online ? "已连接 api.bilibili.com" : "连接失败"}');
  print('访客身份    : ${direct.identity}');
  print('');

  final cases = <String, Map<String, String>>{
    '/api/feed': <String, String>{'ps': '5', 'fresh_idx': '1'},
    '/api/rank': <String, String>{'rid': '0'},
    '/api/popular': <String, String>{'pn': '1', 'ps': '5'},
    '/api/search': <String, String>{'keyword': '原神', 'page': '1'},
    '/api/video': <String, String>{'bvid': 'BV14W4B6sEze'},
    '/api/reply': <String, String>{
      'aid': '117568337608814',
      'pn': '1',
      'ps': '5',
      'sort': '2'
    },
  };

  var passed = 0;
  for (final entry in cases.entries) {
    try {
      final result = await direct.fetch(entry.key, entry.value);
      final count = _count(result.data);
      final title = _title(result.data);
      final ok = count > 0;
      if (ok) passed++;
      print('${ok ? "PASS" : "WARN"}  ${entry.key.padRight(14)} '
          'source=${result.source.padRight(6)} count=$count');
      if (title.isNotEmpty) {
        print('     首条: ${title.length > 46 ? title.substring(0, 46) : title}');
      }
    } catch (e) {
      print('FAIL  ${entry.key.padRight(14)} $e');
    }
  }

  print('');
  print('缓存条目    : ${direct.cacheEntries}');
  print('结果        : $passed/${cases.length} 个接口返回实时数据');
  if (passed == 0) {
    throw StateError('所有直连接口均失败，请检查网络或上游风控');
  }
  // 确保 json 转换确实可用于上层解析
  json.encode(direct.cacheEntries);
}
