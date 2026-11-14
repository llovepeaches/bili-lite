import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// 扫码登录失败。
class QrLoginException implements Exception {
  const QrLoginException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// 一次扫码挑战：把 [url] 编成二维码给用户扫，用 [key] 轮询状态。
class QrChallenge {
  const QrChallenge({
    required this.url,
    required this.key,
    required this.createdAt,
  });

  final String url;
  final String key;
  final DateTime createdAt;

  /// B 站二维码有效期约 180 秒，留 10 秒余量。
  static const Duration lifetime = Duration(seconds: 170);

  bool get isExpired =>
      DateTime.now().difference(createdAt) >= lifetime;
}

enum QrPollState { waiting, scanned, expired, success, failed }

class QrPollResult {
  const QrPollResult({
    required this.state,
    required this.message,
    this.cookie = '',
    this.rawUrl = '',
  });

  final QrPollState state;
  final String message;
  final String cookie;
  final String rawUrl;
}

/// 扫码登录拿到的公开资料。
class QrUser {
  const QrUser({
    required this.mid,
    required this.name,
    required this.face,
    required this.vipLabel,
  });

  final String mid;
  final String name;
  final String face;
  final String vipLabel;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mid': mid,
        'name': name,
        'face': face,
        'vipLabel': vipLabel,
      };

  factory QrUser.fromJson(Map<String, dynamic> json) => QrUser(
        mid: (json['mid'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        face: (json['face'] ?? '').toString(),
        vipLabel: (json['vipLabel'] ?? '').toString(),
      );
}

/// B 站 Web 扫码登录（客户端直连，不需要开放平台凭证 / 不需要 client_secret）。
///
/// 三个上游接口：
///   generate  GET  passport.bilibili.com/x/passport-login/web/qrcode/generate
///   poll      GET  passport.bilibili.com/x/passport-login/web/qrcode/poll
///   nav       GET  api.bilibili.com/x/web-interface/nav
///
/// 原生端（Android / iOS / 桌面）直接请求 B 站；Web 端受同源策略限制，
/// 走同源 BFF 的 `/api/qr/*` 代理（服务端只做协议转发，不留存 Cookie）。
///
/// 与官方 OAuth 的区别必须如实说明：这条链路拿到的是 **B 站 Web 登录 Cookie**
/// （SESSDATA / bili_jct / DedeUserID 等），会保存在本机，用来请求公开接口。
/// 它不经过开放平台、拿不到 access_token，也不提供 scope 授权。
class QrLoginApi {
  QrLoginApi._();
  static final QrLoginApi instance = QrLoginApi._();

  final http.Client _client = http.Client();

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String _referer = 'https://www.bilibili.com/';

  /// Web 端走同源 BFF 代理：UA / Referer 由服务端注入。
  /// 浏览器禁止 JS 设置这两个头（会打印 "Refused to set unsafe header"），
  /// 所以这里必须按平台分开，否则每次请求都污染控制台。
  /// 原生端直连 B 站，需要自己带齐这两项规避风控。
  Map<String, String> get _headers => kIsWeb
      ? const <String, String>{
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        }
      : <String, String>{
          'User-Agent': _ua,
          'Referer': _referer,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        };

  /// 从 B 站响应里取 data；同时兼容 BFF 代理返回的统一结构。
  Map<String, dynamic> _data(http.Response res, String what) {
    if (res.statusCode != 200) {
      throw QrLoginException('$what 返回 HTTP ${res.statusCode}',
          status: res.statusCode);
    }
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(
          json.decode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw QrLoginException('$what 返回内容格式异常', status: res.statusCode);
    }
    final code = decoded['code'];
    if (code is num && code != 0) {
      throw QrLoginException(
          '$what 失败：${decoded['message'] ?? '未知错误'}（code=$code）');
    }
    final data = decoded['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw QrLoginException('连接 B 站登录服务失败，请检查网络：$e');
    }
  }

  /// nav 专用：带上扫码得到的登录 Cookie。
  Future<http.Response> _getWithCookie(String cookie) async {
    try {
      return await _client
          .get(
            Uri.https('api.bilibili.com', '/x/web-interface/nav'),
            headers: <String, String>{..._headers, 'Cookie': cookie},
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw QrLoginException('读取账号资料失败，请检查网络：$e');
    }
  }

  Future<http.Response> _post(Uri uri, Map<String, dynamic> body) async {    try {
      return await _client
          .post(
            uri,
            headers: <String, String>{
              ..._headers,
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(json.encode(body)),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw QrLoginException('连接 B 站登录服务失败，请检查网络：$e');
    }
  }

  Uri _bff(String path, [Map<String, String>? query]) {
    final raw = ApiConfig.url(path, query);
    return raw.startsWith('http') ? Uri.parse(raw) : Uri.base.resolve(raw);
  }

  /// 生成二维码。Web 走 BFF 代理，原生直连。
  Future<QrChallenge> generate() async {
    final Uri uri;
    if (kIsWeb) {
      uri = _bff('/api/qr/generate');
    } else {
      uri = Uri.https('passport.bilibili.com',
          '/x/passport-login/web/qrcode/generate',
          <String, String>{'source': 'main_web'});
    }
    final data = _data(await _get(uri), '获取二维码');
    final url = (data['url'] ?? '').toString();
    final key = (data['qrcodeKey'] ?? data['qrcode_key'] ?? '').toString();
    if (url.isEmpty || key.isEmpty) {
      throw QrLoginException('二维码响应缺少 url / qrcode_key');
    }
    return QrChallenge(url: url, key: key, createdAt: DateTime.now());
  }

  /// 轮询一次扫码状态。
  Future<QrPollResult> poll(String key) async {
    late http.Response res;
    if (kIsWeb) {
      res = await _get(_bff('/api/qr/poll', <String, String>{'key': key}));
    } else {
      res = await _get(Uri.https(
        'passport.bilibili.com',
        '/x/passport-login/web/qrcode/poll',
        <String, String>{'qrcode_key': key, 'source': 'main_web'},
      ));
    }

    // poll 在「二维码失效」时 code 仍为 0，业务码在 data.code 里，
    // 不能按外层 code != 0 直接抛错。
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(
          json.decode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw QrLoginException('扫码状态返回内容格式异常', status: res.statusCode);
    }
    if (res.statusCode != 200) {
      throw QrLoginException('扫码状态返回 HTTP ${res.statusCode}',
          status: res.statusCode);
    }
    final data = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : <String, dynamic>{};

    final state = _stateOf(data['code'] ?? data['state']);
    final message = (data['message'] ?? decoded['message'] ?? '').toString();
    final rawUrl = (data['url'] ?? '').toString();
    final cookie = kIsWeb
        ? (data['cookie'] ?? '').toString()
        : buildCookie(res.headers, rawUrl);
    return QrPollResult(
      state: state,
      message: message.isEmpty ? _defaultMessage(state) : message,
      cookie: cookie,
      rawUrl: rawUrl,
    );
  }

  static QrPollState _stateOf(dynamic raw) {
    if (raw is String) {
      switch (raw) {
        case 'waiting':
          return QrPollState.waiting;
        case 'scanned':
          return QrPollState.scanned;
        case 'expired':
          return QrPollState.expired;
        case 'success':
          return QrPollState.success;
        default:
          return QrPollState.failed;
      }
    }
    final code = raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1;
    switch (code) {
      case 86101:
        return QrPollState.waiting;
      case 86090:
        return QrPollState.scanned;
      case 86038:
      case 86039:
        return QrPollState.expired;
      case 0:
        return QrPollState.success;
      default:
        return QrPollState.failed;
    }
  }

  static String _defaultMessage(QrPollState state) {
    switch (state) {
      case QrPollState.waiting:
        return '请用 B 站 App 扫描二维码';
      case QrPollState.scanned:
        return '已扫码，请在手机上点「确认登录」';
      case QrPollState.expired:
        return '二维码已失效，请重新生成';
      case QrPollState.success:
        return '登录成功';
      case QrPollState.failed:
        return '扫码状态异常，请重新生成二维码';
    }
  }

  /// 用登录 Cookie 调 nav 拿昵称 / 头像 / mid。
  Future<QrUser> profile(String cookie) async {
    if (cookie.isEmpty) {
      throw QrLoginException('登录凭证为空，无法读取资料');
    }
    Map<String, dynamic> data;
    if (kIsWeb) {
      data = _data(
        await _post(_bff('/api/qr/nav'), <String, dynamic>{'cookie': cookie}),
        '读取账号资料',
      );
      return QrUser(
        mid: (data['mid'] ?? '').toString(),
        name: (data['name'] ?? '').toString(),
        face: (data['face'] ?? '').toString(),
        vipLabel: (data['vipLabel'] ?? '').toString(),
      );
    }
    // nav 必须带登录 Cookie，否则 isLogin=false。
    final authed = await _getWithCookie(cookie);
    data = _data(authed, '读取账号资料');
    final isLogin = data['isLogin'] == true;
    if (!isLogin) {
      throw QrLoginException('登录态无效或已过期，请重新扫码');
    }
    final vip = data['vipStatus'] == 1 || data['vipStatus'] == 2;
    return QrUser(
      mid: (data['mid'] ?? '').toString(),
      name: (data['uname'] ?? data['name'] ?? '').toString(),
      face: (data['face'] ?? '').toString(),
      vipLabel: vip ? '大会员' : '',
    );
  }

  /// 把 Set-Cookie 响应头与回调 URL 里的参数合成 Cookie 串。
  ///
  /// B 站 poll 成功时会同时给出：
  ///   * `Set-Cookie: SESSDATA=...; Path=/; ...`（可能多段）
  ///   * `data.url`: `https://...?SESSDATA=...&bili_jct=...&DedeUserID=...`
  /// 两处都取、以 URL 参数优先，避免 Dart http 把多个 Set-Cookie 合并成
  /// 一个难解析的字符串时丢字段。
  static String buildCookie(Map<String, String> headers, String rawUrl) {
    final values = <String, String>{};

    void put(String key, String value) {
      if (value.isEmpty) return;
      values[key] = value;
    }

    const wanted = <String>[
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
      'buvid3',
      'buvid4',
    ];

    final setCookie = headers['set-cookie'] ?? '';
    // 形如 `SESSDATA=xxx; expires=...; Path=/, bili_jct=yyy; ...`
    for (final part in setCookie.split(RegExp(r';\s*|,\s*(?=[A-Za-z_])'))) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final key = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (wanted.contains(key)) put(key, value);
    }

    if (rawUrl.isNotEmpty) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && uri.query.isNotEmpty) {
        // 不能用 uri.queryParameters：它会 URL 解码，把 SESSDATA 里的
        // `%2C` / `%2A` 还原成逗号 / 星号，Cookie 值就坏了。
        // 这里直接切原始 query，保留百分号编码。
        for (final pair in uri.query.split('&')) {
          final i = pair.indexOf('=');
          if (i <= 0) continue;
          final key = Uri.decodeComponent(pair.substring(0, i));
          final value = pair.substring(i + 1);
          if (wanted.contains(key)) put(key, value);
        }
      }
    }

    // 缺 SESSDATA / bili_jct 就不是可用登录态，宁可失败也不要存半套凭证。
    if (!values.containsKey('SESSDATA') || !values.containsKey('bili_jct')) {
      return '';
    }
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
