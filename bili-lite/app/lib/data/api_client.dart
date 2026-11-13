import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../core/api_paths.dart';
import '../core/config.dart';
import '../core/partitions.dart';
import 'bili_direct.dart';
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
/// 三条数据链路，按优先级：
///   1. Web（浏览器 CORS 限制）→ 同源 BFF 代理；
///   2. 原生端 → 直连 B 站公开接口，拿到的是真正的实时数据；
///   3. 直连失败 / `--dart-define=OFFLINE=1` → 内置离线快照兜底。
/// 因此独立安装包既不需要电脑上的 BFF，断网时也不会白屏。
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
    if (ApiConfig.direct) {
      return _direct<T>(path, query, parse);
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
  // 原生端直连 B 站：成功用实时数据，异常自动降级内置快照
  // ------------------------------------------------------------------

  Future<ApiResponse<T>> _direct<T>(
    String path,
    Map<String, String>? query,
    T Function(dynamic raw) parse,
  ) async {
    // 分区表等静态配置不必联网，直接复用快照里的同一份定义。
    if (path == ApiPaths.meta) {
      final snap = await _loadSnapshot();
      return ApiResponse<T>(
        data: parse(_payload(snap, path, query ?? const <String, String>{})),
        source: 'static',
      );
    }
    if (path == ApiPaths.health) {
      return ApiResponse<T>(data: parse(await _directHealth()), source: 'bili');
    }

    try {
      final result = await BiliDirect.instance
          .fetch(path, query ?? const <String, String>{});
      return ApiResponse<T>(data: parse(result.data), source: result.source);
    } catch (_) {
      // 断网、风控、上游变更都走这里，页面照常可用，来源标记成「离线·陈旧」。
      final fallback = await _offline<T>(path, query, parse);
      return ApiResponse<T>(
          data: fallback.data, source: 'mock', stale: true);
    }
  }

  /// 真实探活一次 B 站接口，让设置页如实显示「已连接 / 已降级」。
  Future<Map<String, dynamic>> _directHealth() async {
    final online = await BiliDirect.instance.probe();
    String snapshotAt = '';
    try {
      final snap = await _loadSnapshot();
      snapshotAt = snap['snapshotAt']?.toString() ?? '';
    } catch (_) {}
    return <String, dynamic>{
      'version': '1.2.0',
      'mockMode': !online,
      'identity': online
          ? '直连 B 站 · ${BiliDirect.instance.identity}'
          : '连接失败 · 已降级离线快照',
      'snapshotAt': snapshotAt,
      'cacheEntries': BiliDirect.instance.cacheEntries,
      'webBuild': false,
      'uptime': 0,
    };
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
      case ApiPaths.health:
        return <String, dynamic>{
          'version': '1.2.0',
          'mockMode': true,
          'identity': '内置离线快照',
          'snapshotAt': s['snapshotAt'] ?? '',
          'cacheEntries': 0,
          'webBuild': false,
          'uptime': 0,
        };
      case ApiPaths.meta:
        return <String, dynamic>{
          'partitions': _partitions,
          'replySorts': <Map<String, dynamic>>[
            <String, dynamic>{'value': 2, 'label': '热门'},
            <String, dynamic>{'value': 0, 'label': '按时间'},
          ],
        };
      case ApiPaths.feed:
        return s['feed'] ?? <dynamic>[];
      case ApiPaths.popular:
        return s['popular'] ?? <dynamic>[];
      case ApiPaths.rank:
        return s['rank'] ??
            <String, dynamic>{'note': '', 'list': <dynamic>[]};
      case ApiPaths.reply:
        return s['reply'] ??
            <String, dynamic>{'count': 0, 'list': <dynamic>[]};
      case ApiPaths.search:
        return _search(s, q['keyword'] ?? '');
      case ApiPaths.video:
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

  /// 内置离线快照里的分区表。
  /// 重构前这里和 app_state.dart 各存了一份，且前者 20 项、后者 12 项，
  /// 导致离线 / 在线两种模式下排行榜分区条数量不一致。现在统一用
  /// `BiliPartitions.items` 这一份数据源。
  static List<Map<String, dynamic>> get _partitions => BiliPartitions.items
      .map((p) => <String, dynamic>{'rid': p.rid, 'name': p.name})
      .toList(growable: false);
}
