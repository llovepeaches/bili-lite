import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_paths.dart';
import 'inflate.dart';

/// 一次直连请求的结果。`data` 与 BFF `/api/*` 的 `data` 字段完全同构，
/// 因此 repository 里的解析函数可以原样复用。
class DirectResult {
  const DirectResult(this.data, this.source);

  final dynamic data;
  final String source;
}

class _CacheEntry {
  const _CacheEntry(this.value, this.expireAt);

  final dynamic value;
  final int expireAt;
}

/// 原生端（Android / iOS / Windows / macOS / Linux）直连 B 站公开接口。
///
/// 存在的理由：独立安装包不依赖用户电脑上跑着 Node BFF，也能拿到真正的
/// B 站实时数据。浏览器受 CORS 限制，Web 端仍走同源 BFF 代理。
///
/// 与 server/src/normalize.js 保持同一套归一化规则：上游改字段时两处同步。
/// 任何一步失败都会向 `ApiClient` 抛错，由后者降级到内置离线快照。
class BiliDirect {
  BiliDirect._();

  static final BiliDirect instance = BiliDirect._();

  static const String host = 'api.bilibili.com';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 实测可用的兜底访客身份，仅当 spi 接口不可达时使用。
  static const String _fallbackCookie =
      'buvid3=CB62BB7E-D5EA-B569-B6C2-60BFEF7FB92D13930infoc; '
      'buvid4=C44E6D04-3F20-97E8-3414-5084AEC6B50313930-026110919-hfNN70iV4anbGzHTbpMRFQ==';

  final http.Client _client = http.Client();
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  String _cookie = _fallbackCookie;
  String _identity = '内置访客身份';
  bool _identityTried = false;

  int get cacheEntries => _cache.length;
  String get identity => _identity;

  /// 当前访客身份的 Cookie 头值。
  ///
  /// 播放器（video_player / ExoPlayer）直连 B 站 CDN 时需要它：
  /// CDN 除了 referer 还会校验访客身份，缺了就直接 403。
  String get cookieHeader => _cookie;

  /// 轻量探活：给设置页判断是否真的连上了 B 站。
  Future<bool> probe() async {
    try {
      await _getJson('/x/web-interface/popular', <String, String>{
        'pn': '1',
        'ps': '1',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 启动时换一次真实 buvid3/buvid4，降低被风控页拦截的概率。
  Future<void> _ensureIdentity() async {
    if (_identityTried) return;
    _identityTried = true;
    try {
      final res = await _client
          .get(
            Uri.https(host, '/x/frontend/finger/spi'),
            headers: _headers(_fallbackCookie),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return;
      final data = decoded['data'];
      if (data is! Map) return;
      final b3 = data['b_3'];
      final b4 = data['b_4'];
      if (b3 != null && b4 != null) {
        _cookie = 'buvid3=$b3; buvid4=$b4';
        _identity = '动态获取 (spi)';
      }
    } catch (_) {
      // 兜底身份继续可用，不阻塞业务请求。
    }
  }

  Map<String, String> _headers(String cookie) => <String, String>{
        'User-Agent': _userAgent,
        'Referer': 'https://www.bilibili.com/',
        'Accept': 'application/json, text/plain, */*',
        'Cookie': cookie,
      };

  /// 统一请求出口：必须是 200 + UTF-8 JSON + code === 0，风控 HTML 一律当错误。
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params,
  ) async {
    await _ensureIdentity();
    final uri = Uri.https(host, path, params);
    final res = await _client
        .get(uri, headers: _headers(_cookie))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('B 站返回 HTTP ${res.statusCode}');
    }
    final decoded = json.decode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('B 站返回的不是 JSON 对象（可能被风控拦截）');
    }
    final body = Map<String, dynamic>.from(decoded);
    if (body['code'] != 0) {
      throw StateError('B 站返回 code=${body['code']}: ${body['message'] ?? ''}');
    }
    final data = body['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
  }

  /// 带 TTL 的进程内缓存；上游失败时允许返回陈旧缓存。
  Future<DirectResult> _cached(
    String key,
    int ttlSeconds,
    Future<dynamic> Function() producer, {
    bool skipCache = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hit = _cache[key];
    if (!skipCache && hit != null && hit.expireAt > now) {
      return DirectResult(hit.value, 'cache');
    }
    try {
      final value = await producer();
      _cache[key] = _CacheEntry(value, now + ttlSeconds * 1000);
      return DirectResult(value, 'bili');
    } catch (_) {
      if (hit != null) return DirectResult(hit.value, 'cache');
      rethrow;
    }
  }

  /// 路由到各上游接口。path 沿用 BFF 的 `/api/*`，便于上层零改动。
  Future<DirectResult> fetch(String path, Map<String, String> q) async {
    switch (path) {
      case ApiPaths.feed:
        return _cached('feed:${q['ps']}:${q['fresh_idx']}', 60, () => _feed(q),
            skipCache: q['skip_cache'] == '1');
      case ApiPaths.rank:
        return _cached('rank:${q['rid']}', 300, () => _rank(q),
            skipCache: q['skip_cache'] == '1');
      case ApiPaths.popular:
        return _cached('popular:${q['pn']}:${q['ps']}', 120, () => _popular(q),
            skipCache: q['skip_cache'] == '1');
      case ApiPaths.search:
        final keyword = (q['keyword'] ?? '').trim();
        if (keyword.isEmpty) {
          return const DirectResult(<String, dynamic>{
            'page': 1,
            'pages': 0,
            'total': 0,
            'list': <dynamic>[],
          }, 'empty');
        }
        return _cached('search:$keyword:${q['page']}', 120, () => _search(q));
      case ApiPaths.video:
        return _cached('video:${q['bvid'] ?? q['aid']}', 600, () => _detail(q));
      case ApiPaths.reply:
        return _cached('reply:${q['aid']}:${q['pn']}:${q['ps']}:${q['sort']}',
            120, () => _reply(q));
      case ApiPaths.playurl:
        return _cached(
            'playurl:${q['bvid']}:${q['cid']}:${q['qn']}', 300, () => _playurl(q));
      case ApiPaths.danmaku:
        return _cached('danmaku:${q['oid']}', 300, () => _danmaku(q));
      default:
        throw ArgumentError('未知直连接口 $path');
    }
  }

  /* --------------------------- 上游适配器 --------------------------- */

  /// 播放地址（应用内播放）。
  ///
  /// 与 BFF 的 `normalizePlayurl` 保持同一套字段，客户端解析函数可以复用。
  Future<Map<String, dynamic>> _playurl(Map<String, String> q) async {
    final data = await _getJson('/x/player/playurl', <String, String>{
      'bvid': q['bvid'] ?? '',
      'cid': q['cid'] ?? '',
      'qn': q['qn'] ?? '64',
      // fnval=1 只返回 durl（单文件 mp4）；DASH 需要合流器，放弃。
      'fnval': '1',
      'fourk': '1',
      'platform': 'html5',
      'high_quality': '1',
    });
    final durl = data['durl'];
    final first = (durl is List && durl.isNotEmpty && durl.first is Map)
        ? Map<String, dynamic>.from(durl.first as Map)
        : <String, dynamic>{};
    final quality = _int(data['quality']);
    return <String, dynamic>{
      'url': _string(first['url']),
      'backupUrl': _string(first['backup_url']),
      'size': _int(first['size']),
      'quality': quality,
      'acceptQuality': _list(data['accept_quality']).map(_int).toList(),
      'acceptDescription': _list(data['accept_description'])
          .map((e) => e is Map ? _string(e['value_desc']) : _string(e))
          .toList(),
      'format': _string(data['format']),
      'timelength': _int(data['timelength']),
      'qualityLabel': _qualityLabel(quality, data),
    };
  }

  /// 弹幕列表。
  ///
  /// 上游返回的是 deflate(raw) 压缩的 XML，需要先解压再解析。
  Future<Map<String, dynamic>> _danmaku(Map<String, String> q) async {
    final oid = q['oid'] ?? q['cid'] ?? '';
    final uri = Uri.https(host, '/x/v1/dm/list.so', <String, String>{'oid': oid});
    final res = await _client
        .get(uri, headers: _headers(_cookie))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('弹幕接口返回 HTTP ${res.statusCode}');
    }
    final xml = inflateRawToString(res.bodyBytes);
    final list = _parseDanmakuXml(xml);
    return <String, dynamic>{'count': list.length, 'list': list};
  }

  /// 解析弹幕 XML。
  ///
  /// 形如 `<d p="时间(秒),模式,字号,颜色,发送时间,随机种子,用户ID,行ID">文本</d>`。
  static List<Map<String, dynamic>> _parseDanmakuXml(String xml) {
    final out = <Map<String, dynamic>>[];
    final reg = RegExp(r'<d\s+p="([^"]*)"[^>]*>([\s\S]*?)</d>');
    for (final m in reg.allMatches(xml)) {
      final fields = m.group(1)!.split(',');
      if (fields.length < 4) continue;
      final text = _decodeXml(m.group(2) ?? '');
      if (text.isEmpty) continue;
      out.add(<String, dynamic>{
        'time': (_toDouble(fields[0]) * 1000).round(),
        'mode': _int(fields[1]),
        'size': _int(fields[2]),
        'color': _int(fields[3]),
        'text': text,
      });
    }
    return out;
  }

  static String _decodeXml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .trim();

  static double _toDouble(String s) {
    final v = double.tryParse(s.trim());
    return v ?? 0;
  }

  static String _qualityLabel(int quality, Map<String, dynamic> data) {
    const names = <int, String>{
      120: '4K 超清',
      116: '1080P 60帧',
      112: '1080P 高码率',
      80: '1080P',
      74: '720P 60帧',
      64: '720P',
      32: '480P',
      16: '360P 流畅',
    };
    final hit = names[quality];
    if (hit != null) return hit;
    for (final raw in _list(data['accept_description'])) {
      if (raw is Map && _int(raw['value']) == quality) {
        final desc = _string(raw['value_desc'] ?? raw['desc']);
        if (desc.isNotEmpty) return desc;
      }
    }
    return '$quality';
  }

  Future<List<dynamic>> _feed(Map<String, String> q) async {
    final idx = q['fresh_idx'] ?? '1';
    final data = await _getJson(
      '/x/web-interface/index/top/feed/rcmd',
      <String, String>{
        'ps': q['ps'] ?? '20',
        'fresh_type': '3',
        'fresh_idx': idx,
        'fresh_idx_1h': idx,
      },
    );
    final out = <dynamic>[];
    for (final raw in _list(data['item'])) {
      final item = _map(raw);
      final goto = _string(item['goto']);
      if (goto != 'av' && _string(item['bvid']).isEmpty) continue;
      final reason = _reasonText(item['rcmd_reason']);
      final owner = _map(item['owner']);
      final v = _video(<String, dynamic>{
        'aid': item['id'],
        'bvid': item['bvid'],
        'cid': item['cid'],
        'title': item['title'],
        'cover': item['pic'],
        'durationSeconds': item['duration'],
        'owner': _owner(
            owner['mid'], owner['name'], owner['face']),
        'stat': _stat(_map(item['stat'])),
        'pubdate': item['pubdate'],
        'tname': item['tname'],
        'reason': reason,
      });
      if (_string(v['bvid']).isNotEmpty) out.add(v);
    }
    return out;
  }

  Future<Map<String, dynamic>> _rank(Map<String, String> q) async {
    final data = await _getJson(
      '/x/web-interface/ranking/v2',
      <String, String>{'rid': q['rid'] ?? '0', 'type': 'all'},
    );
    final list = _list(data['list']).map(_rankItem).where(_hasBvid).toList();
    return <String, dynamic>{
      'note': _string(data['note']),
      'list': list,
    };
  }

  Future<List<dynamic>> _popular(Map<String, String> q) async {
    final data = await _getJson(
      '/x/web-interface/popular',
      <String, String>{'pn': q['pn'] ?? '1', 'ps': q['ps'] ?? '20'},
    );
    return _list(data['list']).map(_rankItem).where(_hasBvid).toList();
  }

  Future<Map<String, dynamic>> _search(Map<String, String> q) async {
    final data = await _getJson(
      '/x/web-interface/search/type',
      <String, String>{
        'search_type': 'video',
        'keyword': q['keyword'] ?? '',
        'page': q['page'] ?? '1',
      },
    );
    final items = <dynamic>[];
    for (final raw in _list(data['result'])) {
      final item = _map(raw);
      if (_string(item['type']) != 'video') continue;
      final v = _video(<String, dynamic>{
        'aid': item['aid'] ?? item['id'],
        'bvid': item['bvid'],
        'title': item['title'],
        'cover': item['pic'],
        'duration': item['duration'],
        'owner': _owner(item['mid'], item['author'] ?? item['uname'],
            item['upic'] ?? item['uface']),
        'stat': _stat(<String, dynamic>{
          'view': item['play'],
          'danmaku': item['video_review'],
          'reply': item['review'],
          'like': item['like'],
          'favorite': item['favorites'],
        }),
        'pubdate': item['pubdate'],
        'desc': item['description'] ?? item['desc'],
        'tname': item['typename'],
      });
      if (_string(v['bvid']).isNotEmpty) items.add(v);
    }
    return <String, dynamic>{
      'page': _int(data['page']) == 0 ? 1 : _int(data['page']),
      'pages': _int(data['numPages']),
      'total': _int(data['numResults']),
      'list': items,
    };
  }

  Future<Map<String, dynamic>> _detail(Map<String, String> q) async {
    final params = <String, String>{};
    if ((q['bvid'] ?? '').isNotEmpty) {
      params['bvid'] = q['bvid']!;
    } else {
      params['aid'] = q['aid'] ?? '';
    }
    final data = await _getJson('/x/web-interface/view', params);
    if (_string(data['bvid']).isEmpty) {
      throw const FormatException('视频详情为空');
    }
    final owner = _map(data['owner']);
    final base = _video(<String, dynamic>{
      'aid': data['aid'],
      'bvid': data['bvid'],
      'cid': data['cid'],
      'title': data['title'],
      'cover': data['pic'],
      'durationSeconds': data['duration'],
      'owner': _owner(owner['mid'], owner['name'], owner['face']),
      'stat': _stat(_map(data['stat'])),
      'pubdate': data['pubdate'],
      'desc': data['desc'],
      'tname': data['tname'],
    });
    final pages = <dynamic>[];
    for (final raw in _list(data['pages'])) {
      final p = _map(raw);
      final secs = _int(p['duration']);
      pages.add(<String, dynamic>{
        'cid': _string(p['cid']),
        'page': _int(p['page']),
        'part': _clean(p['part']),
        'duration': secs,
        'durationText': _durationText(secs),
      });
    }
    return <String, dynamic>{
      ...base,
      'pages': pages,
      'dynamic': _clean(data['dynamic']),
      'tags': <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> _reply(Map<String, String> q) async {
    final data = await _getJson('/x/v2/reply', <String, String>{
      'type': '1',
      'oid': q['aid'] ?? '',
      'pn': q['pn'] ?? '1',
      'ps': q['ps'] ?? '20',
      'sort': q['sort'] ?? '2',
    });
    final list = <dynamic>[];
    for (final raw in _list(data['replies'])) {
      final r = _map(raw);
      final member = _map(r['member']);
      final level = _map(member['level_info']);
      final content = _map(r['content']);
      final control = _map(r['reply_control']);
      final subs = <dynamic>[];
      for (final subRaw in _list(r['replies']).take(3)) {
        final sub = _map(subRaw);
        final subMember = _map(sub['member']);
        final subContent = _map(sub['content']);
        subs.add(<String, dynamic>{
          'id': _string(sub['rpid']),
          'uname': _clean(subMember['uname']),
          'message': _clean(subContent['message']),
          'ctime': _int(sub['ctime']),
        });
      }
      list.add(<String, dynamic>{
        'id': _string(r['rpid']),
        'mid': _string(r['mid']),
        'uname': _clean(member['uname']),
        'avatar': _httpsImage(member['avatar']),
        'level': _int(level['current_level']),
        'message': _clean(content['message']),
        'like': _int(r['like']),
        'replyCount': _int(r['rcount']),
        'ctime': _int(r['ctime']),
        'isTop': control['is_top'] == true,
        'location': _clean(control['location']),
        'replies': subs,
      });
    }
    return <String, dynamic>{
      'count': _int(_map(data['page'])['count']),
      'list': list,
    };
  }

  /* --------------------------- 归一化助手 --------------------------- */

  Map<String, dynamic> _rankItem(dynamic raw) {
    final item = _map(raw);
    final owner = _map(item['owner']);
    return _video(<String, dynamic>{
      'aid': item['aid'],
      'bvid': item['bvid'],
      'cid': item['cid'],
      'title': item['title'],
      'cover': item['pic'],
      'durationSeconds': item['duration'],
      'owner': _owner(owner['mid'], owner['name'], owner['face']),
      'stat': _stat(_map(item['stat'])),
      'pubdate': item['pubdate'],
      'desc': item['desc'],
      'tname': item['tname'],
      'reason': _reasonText(item['rcmd_reason']),
    });
  }

  bool _hasBvid(dynamic v) => _string(_map(v)['bvid']).isNotEmpty;

  Map<String, dynamic> _video(Map<String, dynamic> r) {
    final secs = r.containsKey('durationSeconds')
        ? _int(r['durationSeconds'])
        : _toSeconds(r['duration']);
    return <String, dynamic>{
      'aid': _string(r['aid'] ?? r['id']),
      'bvid': _string(r['bvid']),
      'cid': _string(r['cid']),
      'title': _clean(r['title']),
      'cover': _httpsImage(r['cover'] ?? r['pic']),
      'duration': secs,
      'durationText': _durationText(secs),
      'owner': r['owner'] ?? _owner(r['mid'], r['author'] ?? r['uname'],
          r['uface'] ?? r['upic']),
      'stat': r['stat'] ?? _stat(r),
      'pubdate': _int(r['pubdate']),
      'desc': _clean(r['desc'] ?? r['description']),
      'tname': _clean(r['tname'] ?? r['typename']),
      'reason': _reasonText(r['reason'] ?? r['rcmd_reason'] ?? r['rec_reason']),
    };
  }

  Map<String, dynamic> _owner(dynamic mid, dynamic name, dynamic face) {
    final n = _clean(name);
    return <String, dynamic>{
      'mid': _string(mid),
      'name': n.isEmpty ? '未知 UP 主' : n,
      'face': _httpsImage(face),
    };
  }

  Map<String, dynamic> _stat(Map<String, dynamic> raw) => <String, dynamic>{
        'view': _int(raw['view'] ?? raw['play']),
        'danmaku': _int(raw['danmaku'] ?? raw['video_review']),
        'reply': _int(raw['reply'] ?? raw['review']),
        'like': _int(raw['like']),
        'coin': _int(raw['coin']),
        'favorite': _int(raw['favorite'] ?? raw['favorites']),
        'share': _int(raw['share']),
      };

  String _httpsImage(dynamic value) {
    final s = _string(value);
    if (s.startsWith('//')) return 'https:$s';
    if (s.startsWith('http://')) return 'https://${s.substring(7)}';
    return s;
  }

  String _clean(dynamic value) => _string(value)
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();

  /// 上游 `rcmd_reason` 可能是字符串、对象或对象数组，直接 toString 会得到
  /// "[object Object]"。这里统一收敛成纯文本，与 BFF 侧逻辑保持一致。
  String _reasonText(dynamic value) {
    if (value == null) return '';
    if (value is String) return _clean(value);
    if (value is List) {
      for (final item in value) {
        final text = _reasonText(item);
        if (text.isNotEmpty) return text;
      }
      return '';
    }
    if (value is Map) {
      final candidates = <dynamic>[
        value['content'],
        value['reason'],
        value['text'],
        value['name'],
      ];
      for (final c in candidates) {
        final text = _reasonText(c);
        if (text.isNotEmpty) return text;
      }
      return '';
    }
    return _clean(value.toString());
  }

  int _toSeconds(dynamic value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is double) return value.floor() < 0 ? 0 : value.floor();
    final parts = _string(value).split(':');
    int p(int i) =>
        i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0;
    if (parts.length == 3) return p(0) * 3600 + p(1) * 60 + p(2);
    if (parts.length == 2) return p(0) * 60 + p(1);
    return p(0);
  }

  String _durationText(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String pad(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${pad(m)}:${pad(sec)}' : '${pad(m)}:${pad(sec)}';
  }

  // 这几个基础转换做成 static：新增的弹幕解析与清晰度映射都是静态辅助方法，
  // 需要复用它们。static 成员同样可以在实例方法里直接调用。
  static String _string(dynamic v) => v == null ? '' : v.toString();

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(_string(v)) ?? 0;
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<dynamic> _list(dynamic v) =>
      v is List ? List<dynamic>.from(v) : <dynamic>[];
}
