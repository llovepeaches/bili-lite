import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

class OAuthException implements Exception {
  const OAuthException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// 授权服务端的公开配置。注意：这里永远不会有 client_secret。
class OAuthConfigView {
  const OAuthConfigView({
    required this.configured,
    required this.sandbox,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.missing,
    required this.note,
  });

  final bool configured;
  final bool sandbox;
  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final List<String> missing;
  final String note;

  factory OAuthConfigView.fromJson(Map<String, dynamic> json) {
    return OAuthConfigView(
      configured: json['configured'] == true,
      sandbox: json['sandbox'] == true,
      clientId: (json['clientId'] ?? '').toString(),
      redirectUri: (json['redirectUri'] ?? '').toString(),
      scopes: _strings(json['scopes']),
      missing: _strings(json['missing']),
      note: (json['note'] ?? '').toString(),
    );
  }

  static List<String> _strings(dynamic raw) => raw is List
      ? raw.map((e) => e.toString()).toList(growable: false)
      : const <String>[];
}

/// 一次授权发起的结果。authorizeUrl 指向 B 站官方授权页（或自检用的演示页）。
class OAuthBegin {
  const OAuthBegin({
    required this.authorizeUrl,
    required this.state,
    required this.redirectUri,
    required this.scopes,
    required this.sandbox,
    required this.expiresAt,
  });

  final String authorizeUrl;
  final String state;
  final String redirectUri;
  final List<String> scopes;
  final bool sandbox;
  final int expiresAt;

  factory OAuthBegin.fromJson(Map<String, dynamic> json) {
    return OAuthBegin(
      authorizeUrl: (json['authorizeUrl'] ?? '').toString(),
      state: (json['state'] ?? '').toString(),
      redirectUri: (json['redirectUri'] ?? '').toString(),
      scopes: OAuthConfigView._strings(json['scopes']),
      sandbox: json['sandbox'] == true,
      expiresAt: _int(json['expiresAt']),
    );
  }

  static int _int(dynamic raw) =>
      raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
}

/// 本地持久化的登录凭证。expiresAt 是毫秒级 UTC 绝对时间戳。
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final List<String> scopes;

  bool get isExpired =>
      expiresAt <= 0 ||
      DateTime.now().millisecondsSinceEpoch >= expiresAt;

  /// 剩余不足 5 分钟视为需要续期
  bool get needsRefresh =>
      !isExpired &&
      expiresAt - DateTime.now().millisecondsSinceEpoch < 5 * 60 * 1000;

  String get expiresText {
    if (expiresAt <= 0) return '未知';
    final d = DateTime.fromMillisecondsSinceEpoch(expiresAt).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  factory OAuthTokens.fromJson(Map<String, dynamic> json) {
    return OAuthTokens(
      accessToken: (json['accessToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      expiresAt: OAuthBegin._int(json['expiresAt']),
      scopes: OAuthConfigView._strings(json['scopes']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'scopes': scopes,
      };
}

/// 官方 USER_INFO 返回的公开资料（头像 / 昵称 / openid）。
class BiliUser {
  const BiliUser({
    required this.openid,
    required this.name,
    required this.face,
    required this.scopes,
    required this.sandbox,
  });

  final String openid;
  final String name;
  final String face;
  final List<String> scopes;
  final bool sandbox;

  factory BiliUser.fromJson(Map<String, dynamic> json) {
    return BiliUser(
      openid: (json['openid'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      face: (json['face'] ?? '').toString(),
      scopes: OAuthConfigView._strings(json['scopes']),
      sandbox: json['sandbox'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'openid': openid,
        'name': name,
        'face': face,
        'scopes': scopes,
        'sandbox': sandbox,
      };
}

/// 与 BFF 的 /api/oauth/* 通信。
///
/// 客户端只持有公开配置与最终 token，全程不接触 client_secret、用户密码、
/// Cookie、SESSDATA 或 bili_jct；授权码 code 也不落客户端，由服务端换成一次性
/// ticket 后再领取。
class OAuthApi {
  OAuthApi._();
  static final OAuthApi instance = OAuthApi._();

  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final raw = ApiConfig.oauthUrl(path);
    final uri = raw.startsWith('http') ? Uri.parse(raw) : Uri.base.resolve(raw);
    late http.Response res;
    try {
      if (body == null) {
        res = await _client.get(uri).timeout(const Duration(seconds: 15));
      } else {
        res = await _client
            .post(
              uri,
              headers: const <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: utf8.encode(json.encode(body)),
            )
            .timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      throw OAuthException(
        '无法连接授权服务（${ApiConfig.oauthDisplayBase}）。官方登录需要授权服务端持有 '
        'client_secret，请确认 BFF 已启动或已配置 BFF_URL。',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(
          json.decode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw OAuthException('授权服务返回内容格式异常', status: res.statusCode);
    }

    if (res.statusCode != 200 || decoded['code'] != 0) {
      throw OAuthException(
        (decoded['message'] ?? '授权服务返回错误').toString(),
        status: res.statusCode,
      );
    }
    final data = decoded['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<OAuthConfigView> config() async =>
      OAuthConfigView.fromJson(await _call('/api/oauth/config'));

  Future<OAuthBegin> begin({required bool web}) async => OAuthBegin.fromJson(
        await _call('/api/oauth/begin',
            body: <String, dynamic>{'platform': web ? 'web' : 'native'}),
      );

  Future<OAuthTokens> exchange(String ticket) async => OAuthTokens.fromJson(
        await _call('/api/oauth/exchange',
            body: <String, dynamic>{'ticket': ticket.trim()}),
      );

  Future<OAuthTokens> refresh(OAuthTokens current) async {
    final data = await _call('/api/oauth/refresh', body: <String, dynamic>{
      'refreshToken': current.refreshToken,
      'scopes': current.scopes,
    });
    final next = OAuthTokens.fromJson(data);
    return OAuthTokens(
      accessToken: next.accessToken,
      refreshToken: next.refreshToken,
      expiresAt: next.expiresAt,
      scopes: next.scopes.isEmpty ? current.scopes : next.scopes,
    );
  }

  Future<BiliUser> me(String accessToken) async => BiliUser.fromJson(
        await _call('/api/oauth/me',
            body: <String, dynamic>{'accessToken': accessToken}),
      );

  Future<List<String>> scopes(String accessToken) async {
    final data = await _call('/api/oauth/scopes',
        body: <String, dynamic>{'accessToken': accessToken});
    return OAuthConfigView._strings(data['scopes']);
  }
}
