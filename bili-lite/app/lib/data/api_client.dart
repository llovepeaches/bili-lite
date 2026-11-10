import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

/// 极薄的 HTTP 封装：统一超时、UTF-8 解码、错误码与数据来源解析。
/// 不引入 Dio / Retrofit 之类的重依赖，六个平台都能直接跑。
///
/// `--dart-define=OFFLINE=1` 时完全不发网络请求，改读 assets/offline.json
/// 中的真实数据快照，让独立安装包脱离 BFF 也能开箱即用。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _client = http.Client();

  /// 快照只需解析一次，之后所有页面共用。
  static Map<String, dynamic>? _snapshot;

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? query,
    required T Function(dynamic raw) parse,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (ApiConfig.offline) {
      return _offline<T>(path, query, parse);
    }

    final raw = ApiConfig.url(path, query);
    final uri = raw.startsWith('http') ? Uri.parse(raw) : Uri.base.resolve(raw);

    late http.Response res;
    try {
      res = await _client.get(uri).timeout(timeout);
    } catch (e) {
      throw ApiException('无法连接服务（${ApiConfig.displayBase}），请确认 BFF 已启动');
    }

    if (res.statusCode != 200) {
      throw ApiException('服务返回 HTTP ${res.statusCode}');
    }

    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(
          json.decode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw ApiException('服务返回内容格式异常');
    }

    if (body['code'] != 0) {
      throw ApiException(body['message']?.toString() ?? '接口返回错误');
    }

    final meta = body['meta'] is Map
        ? Map<String, dynamic>.from(body['meta'] as Map)
        : <String, dynamic>{};

    return ApiResponse<T>(
      data: parse(body['data']),
      source: meta['source']?.toString() ?? 'live',
      stale: meta['stale'] == true,
    );
  }

  // ------------------------------------------------------------------
  // 内置离线数据源：与 BFF 的 /api/* 返回结构完全同构
  // ------------------------------------------------------------------

  Future<ApiResponse<T>> _offline<T>(
    String path,
    Map<String, String>? query,
    T Function(dynamic raw) parse,
  ) async {
    try {
      final snap = await _loadSnapshot();
      final data = _payload(snap, path, query ?? const <String, String>{});
      return ApiResponse<T>(data: parse(data), source: 'mock', stale: false);
    } catch (e) {
      throw ApiException('内置数据读取失败：$e');
    }
  }

  Future<Map<String, dynamic>> _loadSnapshot() async {
    final cached = _snapshot;
    if (cached != null) return cached;
    final text = await rootBundle.loadString('assets/offline.json');
    final loaded = Map<String, dynamic>.from(json.decode(text) as Map);
    _snapshot = loaded;
    return loaded;
  }

  dynamic _payload(
      Map<String, dynamic> s, String path, Map<String, String> q) {
    switch (path) {
      case '/api/health':
        return <String, dynamic>{
          'version': '1.2.0',
          'mockMode': true,
          'identity': '内置离线快照',
          'snapshotAt': s['snapshotAt'] ?? '',
          'cacheEntries': 0,
          'webBuild': false,
          'uptime': 0,
        };
      case '/api/meta':
        return <String, dynamic>{
          'partitions': _partitions,
          'replySorts': <Map<String, dynamic>>[
            <String, dynamic>{'value': 2, 'label': '热门'},
            <String, dynamic>{'value': 0, 'label': '按时间'},
          ],
        };
      case '/api/feed':
        return s['feed'] ?? <dynamic>[];
      case '/api/popular':
        return s['popular'] ?? <dynamic>[];
      case '/api/rank':
        return s['rank'] ??
            <String, dynamic>{'note': '', 'list': <dynamic>[]};
      case '/api/reply':
        return s['reply'] ??
            <String, dynamic>{'count': 0, 'list': <dynamic>[]};
      case '/api/search':
        return _search(s, q['keyword'] ?? '');
      case '/api/video':
        return _detail(s, q['bvid'] ?? '', q['aid'] ?? '');
      default:
        return <String, dynamic>{};
    }
  }

  List<dynamic> _allVideos(Map<String, dynamic> s) {
    final all = <dynamic>[];
    for (final key in const <String>['feed', 'popular']) {
      final v = s[key];
      if (v is List) all.addAll(v);
    }
    final rank = s['rank'];
    if (rank is Map && rank['list'] is List) {
      all.addAll(rank['list'] as List);
    }
    final search = s['search'];
    if (search is Map && search['list'] is List) {
      all.addAll(search['list'] as List);
    }
    return all;
  }

  Map<String, dynamic> _search(Map<String, dynamic> s, String keyword) {
    final kw = keyword.trim().toLowerCase();
    final all = _allVideos(s);
    final matched = <dynamic>[];
    for (final v in all) {
      if (v is! Map) continue;
      final title = (v['title'] ?? '').toString().toLowerCase();
      final owner = v['owner'];
      final name = owner is Map
          ? (owner['name'] ?? '').toString().toLowerCase()
          : '';
      if (kw.isEmpty || title.contains(kw) || name.contains(kw)) {
        matched.add(v);
      }
    }
    final seen = <String>{};
    final list = <dynamic>[];
    for (final v in <dynamic>[...matched, ...all]) {
      if (list.length >= 20) break;
      final key = v is Map ? (v['bvid'] ?? '').toString() : '';
      if (key.isNotEmpty && !seen.add(key)) continue;
      list.add(v);
    }
    return <String, dynamic>{
      'page': 1,
      'pages': 1,
      'total': list.length,
      'list': list,
      'keyword': keyword,
    };
  }

  Map<String, dynamic> _detail(
      Map<String, dynamic> s, String bvid, String aid) {
    final detail = s['detail'];
    Map<String, dynamic> base;
    if (detail is Map && (bvid.isEmpty || detail['bvid'] == bvid)) {
      base = Map<String, dynamic>.from(detail);
    } else {
      final all = _allVideos(s);
      Map<String, dynamic>? found;
      for (final v in all) {
        if (v is Map &&
            (v['bvid'] == bvid ||
                (aid.isNotEmpty && v['aid'].toString() == aid))) {
          found = Map<String, dynamic>.from(v);
          break;
        }
      }
      base = found ??
          (all.isNotEmpty && all.first is Map
              ? Map<String, dynamic>.from(all.first as Map)
              : <String, dynamic>{});
    }
    if (bvid.isNotEmpty) base['bvid'] = bvid;
    if (base['pages'] == null) {
      base['pages'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'cid': base['cid'] ?? '',
          'page': 1,
          'part': base['title'] ?? '',
          'duration': base['duration'] ?? 0,
          'durationText': base['durationText'] ?? '',
        }
      ];
    }
    base.putIfAbsent('dynamic', () => '');
    base.putIfAbsent('tags', () => <dynamic>[]);
    return base;
  }

  static const List<Map<String, dynamic>> _partitions =
      <Map<String, dynamic>>[
    <String, dynamic>{'rid': 0, 'name': '全站'},
    <String, dynamic>{'rid': 1, 'name': '动画'},
    <String, dynamic>{'rid': 168, 'name': '国创'},
    <String, dynamic>{'rid': 3, 'name': '音乐'},
    <String, dynamic>{'rid': 129, 'name': '舞蹈'},
    <String, dynamic>{'rid': 4, 'name': '游戏'},
    <String, dynamic>{'rid': 36, 'name': '知识'},
    <String, dynamic>{'rid': 188, 'name': '科技'},
    <String, dynamic>{'rid': 234, 'name': '运动'},
    <String, dynamic>{'rid': 223, 'name': '汽车'},
    <String, dynamic>{'rid': 160, 'name': '生活'},
    <String, dynamic>{'rid': 211, 'name': '美食'},
    <String, dynamic>{'rid': 217, 'name': '动物圈'},
    <String, dynamic>{'rid': 119, 'name': '鬼畜'},
    <String, dynamic>{'rid': 155, 'name': '时尚'},
    <String, dynamic>{'rid': 202, 'name': '资讯'},
    <String, dynamic>{'rid': 5, 'name': '娱乐'},
    <String, dynamic>{'rid': 181, 'name': '影视'},
    <String, dynamic>{'rid': 177, 'name': '纪录片'},
    <String, dynamic>{'rid': 23, 'name': '电影'},
    <String, dynamic>{'rid': 11, 'name': '电视剧'},
  ];
}
