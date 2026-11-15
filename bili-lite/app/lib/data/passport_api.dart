import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'qr_login_api.dart';

/// B 站 Web 登录（账号密码 / 短信验证码 / Cookie）失败。
class PassportException implements Exception {
  const PassportException(this.message, {this.code, this.needsCaptcha = false});

  final String message;
  final int? code;

  /// 是否需要完成人机验证（B 站极验滑块）。
  final bool needsCaptcha;

  @override
  String toString() => message;
}

/// 人机验证挑战（B 站 `/x/passport-login/captcha`）。
///
/// `validate` / `seccode` 必须由极验 JS 在浏览器里完成滑块后产生，
/// 纯 Dart 客户端无法自行生成——本应用不伪造，遇到需要验证时明确引导用户。
class CaptchaChallenge {
  const CaptchaChallenge({
    required this.type,
    required this.token,
    required this.gt,
    required this.challenge,
  });

  final String type;
  final String token;
  final String gt;
  final String challenge;

  bool get isGeetest => type == 'geetest';
}

/// Web 登录 RSA 公钥与一次性 hash。
class PassportKey {
  const PassportKey({required this.hash, required this.pem});
  final String hash;
  final String pem;
}

/// 短信发送结果：`captchaKey` 需原样带回登录接口。
class SmsSendResult {
  const SmsSendResult({required this.captchaKey});
  final String captchaKey;
}

/// 一次上游响应的统一视图（屏蔽「原生直连」与「Web 走 BFF」的差异）。
class _Reply {
  const _Reply(this.code, this.message, this.data, this.cookie);
  final int code;
  final String message;
  final Map<String, dynamic> data;
  final String cookie;
}

/// 解析后的 RSA 公钥（仅 modulus 与 exponent，PKCS#1 v1.5 加密所需）。
class _RsaPublicKey {
  const _RsaPublicKey(this.n, this.e);
  final BigInt n;
  final BigInt e;
}

/// 最小 ASN.1 DER 读取器：只处理 RSA SubjectPublicKeyInfo 需要的
/// SEQUENCE / BIT STRING / INTEGER 三种标签，够用且不引入任何依赖。
class _DerReader {
  _DerReader(this.bytes);
  final List<int> bytes;
  int _pos = 0;

  int _byte() {
    if (_pos >= bytes.length) {
      throw const PassportException('RSA 公钥格式异常（数据截断）');
    }
    return bytes[_pos++];
  }

  int _length() {
    final first = _byte();
    if (first < 0x80) return first;
    final count = first & 0x7f;
    if (count == 0 || count > 4) {
      throw const PassportException('RSA 公钥长度字段异常');
    }
    var len = 0;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | _byte();
    }
    return len;
  }

  List<int> _content(int expectedTag) {
    final tag = _byte();
    if (tag != expectedTag) {
      throw const PassportException('RSA 公钥 DER 标签不匹配');
    }
    final len = _length();
    final start = _pos;
    _pos += len;
    if (start + len > bytes.length) {
      throw const PassportException('RSA 公钥格式异常（内容越界）');
    }
    return bytes.sublist(start, start + len);
  }

  BigInt _integer() {
    final content = _content(0x02);
    var i = 0;
    while (i < content.length - 1 && content[i] == 0) {
      i++;
    }
    var value = BigInt.zero;
    for (; i < content.length; i++) {
      value = (value << 8) | BigInt.from(content[i]);
    }
    return value;
  }
}

/// B 站 Web 登录接口封装。
///
/// 三类入口最终产物都是 **B 站 Web 登录 Cookie**，交给 `QrSession.applyCookie`
/// 统一落地，因此不引入第四套账号状态。
///
/// 平台差异：
///   * 原生端（Android / iOS / 桌面）直连 passport.bilibili.com；
///   * Web 端受 CORS 限制，走同源 BFF 的 `/api/passport/*` 代理（服务端只转发、
///     不落盘 Cookie），与扫码登录的 `/api/qr/*` 是同一套边界。
///
/// **诚实边界**：B 站对 Web 密码/短信登录强制极验滑块（不带 validate/seccode 时
/// 返回 `code=-105 验证码错误`）。极验的 validate/seccode 必须由浏览器里的
/// 极验 JS 产生，纯 Dart 客户端无法生成；本类不伪造，而是把 challenge 暴露出来，
/// 由 UI 明确引导用户改用扫码登录 / Cookie 登录，或在浏览器完成登录后复制 Cookie。
class PassportApi {
  PassportApi._();

  static final PassportApi instance = PassportApi._();

  http.Client _client = http.Client();

  /// 测试注入点：与 `OAuthApi.debugClient` 保持同样的可测性约定。
  @visibleForTesting
  set debugClient(http.Client client) => _client = client;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String _referer = 'https://www.bilibili.com/';
  static const String _passport = 'passport.bilibili.com';
  static const Duration _timeout = Duration(seconds: 15);

  /// 中国大陆手机号区号（短信登录用）。
  static const String defaultCid = '86';

  Map<String, String> get _headers => kIsWeb
      ? const <String, String>{
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json; charset=utf-8',
        }
      : <String, String>{
          'User-Agent': _ua,
          'Referer': _referer,
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        };

  Uri _native(String path, [Map<String, String>? query]) =>
      Uri.https(_passport, path, query);

  Uri _bff(String path, [Map<String, String>? query]) {
    final raw = ApiConfig.url(path, query);
    return raw.startsWith('http') ? Uri.parse(raw) : Uri.base.resolve(raw);
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: _headers).timeout(_timeout);
    } catch (e) {
      throw PassportException('连接 B 站登录服务失败，请检查网络：$e');
    }
  }

  Future<http.Response> _post(Uri uri, Object body) async {
    try {
      return await _client
          .post(uri, headers: _headers, body: body)
          .timeout(_timeout);
    } catch (e) {
      throw PassportException('连接 B 站登录服务失败，请检查网络：$e');
    }
  }

  /// 把上游响应统一成 [_Reply]。
  ///
  /// 原生端直连时从 `Set-Cookie` 与 `data.url` 合成 Cookie；Web 端 BFF 会把
  /// 合成结果放在 `data.cookie`，两条路径对上层完全一致。
  _Reply _decode(http.Response res, String what) {
    if (res.statusCode != 200) {
      throw PassportException('$what 返回 HTTP ${res.statusCode}',
          code: res.statusCode);
    }
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(
          json.decode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw PassportException('$what 返回内容格式异常（疑似风控拦截）');
    }
    final rawCode = decoded['code'];
    final code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse('$rawCode') ?? -1;
    final message = (decoded['message'] ?? '').toString();
    final data = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : <String, dynamic>{};

    String cookie;
    if (kIsWeb) {
      cookie = (data['cookie'] ?? '').toString();
    } else {
      cookie = QrLoginApi.buildCookie(
        res.headers,
        (data['url'] ?? '').toString(),
      );
    }
    if (code != 0) {
      throw PassportException(
        _friendlyMessage(code, message),
        code: code,
        needsCaptcha: _isCaptchaRequired(code),
      );
    }
    return _Reply(code, message, data, cookie);
  }

  /// 把 B 站原始错误码翻译成用户能看懂的提示。
  static String _friendlyMessage(int code, String raw) {
    switch (code) {
      case -105:
        return 'B 站要求完成人机验证（滑块），请在浏览器登录后改用「Cookie 登录」，'
            '或直接使用「扫码登录」。';
      case -400:
        return '请求参数不完整，请检查输入后重试。';
      case -412:
        return '请求被 B 站风控拦截，请稍后再试或改用扫码 / Cookie 登录。';
      case -629:
        return '账号或密码错误。';
      case 2400:
      case 2406:
        return '短信验证码不正确或需要人机验证，请重新获取验证码。';
      case 1000:
        return '该手机号操作过于频繁，请稍后再试。';
      case 1039:
        return '验证码已过期，请重新获取。';
      default:
        return raw.isEmpty ? '登录失败（code=$code）' : '$raw（code=$code）';
    }
  }

  static bool _isCaptchaRequired(int code) =>
      code == -105 || code == -412 || code == 2400 || code == 2406;

  // ------------------------------------------------------------------
  // RSA：纯 Dart 实现 PKCS#1 v1.5，零第三方依赖
  // ------------------------------------------------------------------

  /// 解析 PEM（`-----BEGIN PUBLIC KEY-----`，SubjectPublicKeyInfo）。
  static _RsaPublicKey _parsePublicKey(String pem) {
    try {
      final b64 = pem
          .replaceAll(RegExp(r'-----[^-]*-----'), '')
          .replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(b64);
      final outer = _DerReader(bytes);
      final spki = _contentSeq(outer);
      final seqReader = _DerReader(spki);
      seqReader._content(0x30); // AlgorithmIdentifier，跳过
      final bitString = seqReader._content(0x03);
      if (bitString.isEmpty || bitString[0] != 0) {
        throw const PassportException('RSA 公钥 BIT STRING 异常');
      }
      final rsaSeq = _contentSeq(_DerReader(bitString.sublist(1)));
      final rsa = _DerReader(rsaSeq);
      final n = rsa._integer();
      final e = rsa._integer();
      if (n <= BigInt.zero || e <= BigInt.zero) {
        throw const PassportException('RSA 公钥参数无效');
      }
      return _RsaPublicKey(n, e);
    } on PassportException {
      rethrow;
    } catch (_) {
      throw const PassportException('无法解析 B 站返回的 RSA 公钥');
    }
  }

  static List<int> _contentSeq(_DerReader reader) => reader._content(0x30);

  /// 用 B 站的 `hash + 密码` 做 RSA 加密（PKCS#1 v1.5），返回 base64。
  ///
  /// 拆出 [_encryptWithPadding] 是为了让单测能注入确定性的随机填充，
  /// 用一对 toy RSA 密钥验证加密结果确实可被私钥还原，而不是只会「不报错」。
  static String encryptPassword(
      String hash, String pem, String password) {
    final key = _parsePublicKey(pem);
    final modulusBytes = (key.n.bitLength + 7) ~/ 8;
    final message = utf8.encode('$hash$password');
    final paddingLength = modulusBytes - message.length - 3;
    if (paddingLength < 8) {
      throw const PassportException('RSA 密钥长度不足以加密当前密码');
    }
    final random = Random.secure();
    final padding = List<int>.generate(paddingLength, (_) {
      var byte = random.nextInt(255) + 1; // 1..255，绝不为 0
      return byte;
    });
    return _encryptWithPadding(key, message, padding, modulusBytes);
  }

  @visibleForTesting
  static String encryptWithPaddingForTest(
      String pem, List<int> message, List<int> padding) {
    final key = _parsePublicKey(pem);
    return _encryptWithPadding(
        key, message, padding, (key.n.bitLength + 7) ~/ 8);
  }

  static String _encryptWithPadding(_RsaPublicKey key, List<int> message,
      List<int> padding, int modulusBytes) {
    final encoded = <int>[0x00, 0x02, ...padding, 0x00, ...message];
    var value = BigInt.zero;
    for (final byte in encoded) {
      value = (value << 8) | BigInt.from(byte);
    }
    final cipher = value.modPow(key.e, key.n);
    // 固定补齐到 modulusBytes，前导零不能丢。
    final hex = cipher.toRadixString(16).padLeft(modulusBytes * 2, '0');
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return base64.encode(out);
  }

  // ------------------------------------------------------------------
  // 上游接口
  // ------------------------------------------------------------------

  /// 拉取 Web 登录 RSA 公钥与一次性 hash。
  Future<PassportKey> fetchKey() async {
    final uri = kIsWeb
        ? _bff('/api/passport/key')
        : _native('/x/passport-login/web/key');
    final reply = _decode(await _get(uri), '获取登录密钥');
    final hash = (reply.data['hash'] ?? '').toString();
    final pem = (reply.data['key'] ?? '').toString();
    if (hash.isEmpty || pem.isEmpty) {
      throw const PassportException('登录密钥响应缺少 hash / key');
    }
    return PassportKey(hash: hash, pem: pem);
  }

  /// 拉取极验人机验证参数。
  Future<CaptchaChallenge> fetchCaptcha() async {
    final stamp = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final uri = kIsWeb
        ? _bff('/api/passport/captcha')
        : _native('/x/passport-login/captcha', <String, String>{
            'source': 'main_web',
            't': stamp.toStringAsFixed(3),
          });
    final reply = _decode(await _get(uri), '获取人机验证参数');
    final geetest = reply.data['geetest'] is Map
        ? Map<String, dynamic>.from(reply.data['geetest'] as Map)
        : <String, dynamic>{};
    return CaptchaChallenge(
      type: (reply.data['type'] ?? '').toString(),
      token: (reply.data['token'] ?? '').toString(),
      gt: (geetest['gt'] ?? '').toString(),
      challenge: (geetest['challenge'] ?? '').toString(),
    );
  }

  /// 账号密码登录。[encryptedPassword] 由 [encryptPassword] 生成。
  ///
  /// `validate` / `seccode` 为空时 B 站会要求人机验证（见类注释）。
  Future<String> passwordLogin({
    required String username,
    required String encryptedPassword,
    String token = '',
    String challenge = '',
    String validate = '',
    String seccode = '',
  }) async {
    final form = <String, String>{
      'source': 'main_web',
      'username': username,
      'password': encryptedPassword,
      'keep': '0',
      if (token.isNotEmpty) 'token': token,
      if (challenge.isNotEmpty) 'challenge': challenge,
      if (validate.isNotEmpty) 'validate': validate,
      if (seccode.isNotEmpty) 'seccode': seccode,
    };
    final reply = await _postLogin('/x/passport-login/web/login',
        '/api/passport/password', form, '账号密码登录');
    return _requireCookie(reply, '账号密码登录');
  }

  /// 发送短信验证码。返回 `captcha_key`，登录时原样带回。
  Future<SmsSendResult> sendSmsCode({
    required String tel,
    String cid = defaultCid,
    String token = '',
    String challenge = '',
    String validate = '',
    String seccode = '',
  }) async {
    final form = <String, String>{
      'tel': tel,
      'cid': cid,
      'source': 'main_web',
      if (token.isNotEmpty) 'token': token,
      if (challenge.isNotEmpty) 'challenge': challenge,
      if (validate.isNotEmpty) 'validate': validate,
      if (seccode.isNotEmpty) 'seccode': seccode,
    };
    final reply = await _postLogin('/x/passport-login/web/sms/send',
        '/api/passport/sms/send', form, '发送短信验证码');
    final key = (reply.data['captcha_key'] ?? reply.data['captchaKey'] ?? '')
        .toString();
    if (key.isEmpty) {
      throw const PassportException('验证码已发送，但响应缺少 captcha_key，请重试');
    }
    return SmsSendResult(captchaKey: key);
  }

  /// 用短信验证码登录。
  Future<String> smsLogin({
    required String tel,
    required String code,
    required String captchaKey,
    String cid = defaultCid,
  }) async {
    final form = <String, String>{
      'tel': tel,
      'cid': cid,
      'code': code,
      'captcha_key': captchaKey,
      'source': 'main_web',
    };
    final reply = await _postLogin('/x/passport-login/web/login/sms',
        '/api/passport/sms/login', form, '短信验证码登录');
    return _requireCookie(reply, '短信验证码登录');
  }

  Future<_Reply> _postLogin(String nativePath, String bffPath,
      Map<String, String> form, String what) async {
    final Object body;
    final Uri uri;
    if (kIsWeb) {
      uri = _bff(bffPath);
      body = json.encode(form);
    } else {
      uri = _native(nativePath);
      body = form; // http 包会把 Map 编码成 form-urlencoded
    }
    return _decode(await _post(uri, body), what);
  }

  String _requireCookie(_Reply reply, String what) {
    if (reply.cookie.isEmpty) {
      throw PassportException('$what 未返回可用登录凭证，请改用扫码登录或 Cookie 登录');
    }
    return reply.cookie;
  }

  // ------------------------------------------------------------------
  // Cookie 登录
  // ------------------------------------------------------------------

  /// 把用户粘贴的 Cookie 规范化成 `SESSDATA=...; bili_jct=...; ...`。
  ///
  /// 兼容三种常见粘贴形式：DevTools 复制的整串（`;` 分隔）、URL query（`&` 分隔）、
  /// 以及只填了 `SESSDATA` / `bili_jct` 的极简形式。**缺任一必填字段直接报错**，
  /// 不把半套凭证写进本地，避免后续所有请求都以「未登录」失败却查不出原因。
  static String normalizeCookie(String raw) {
    const wanted = <String>[
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
      'buvid3',
      'buvid4',
    ];
    final values = <String, String>{};
    final text = raw.trim();
    if (text.isEmpty) {
      throw const PassportException('请先粘贴 B 站登录 Cookie');
    }
    for (final pair in text.split(RegExp(r'[;&,\n]\s*'))) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final key = pair.substring(0, i).trim().replaceFirst(RegExp(r'^\.+'), '');
      final value = pair.substring(i + 1).trim();
      if (wanted.contains(key) && value.isNotEmpty) values[key] = value;
    }
    if (!values.containsKey('SESSDATA') || !values.containsKey('bili_jct')) {
      throw const PassportException(
          'Cookie 必须同时包含 SESSDATA 和 bili_jct，请复制完整登录 Cookie');
    }
    // 按白名单的固定顺序输出，而不是用户粘贴的顺序：结果可预测、可测，
    // 且 SESSDATA / bili_jct 永远排在最前面，排查凭证问题时一眼能看见。
    return wanted
        .where((String k) => values.containsKey(k))
        .map((String k) => '$k=${values[k]}')
        .join('; ');
  }

  /// 用 nav 校验 Cookie 是否真的有效，并读取账号资料。
  ///
  /// 把 [QrLoginException] 收敛成 [PassportException]，让「三种登录方式」
  /// 的调用方只需处理一种异常类型，错误文案也能直接展示给用户。
  Future<QrUser> verifyCookie(String cookie) async {
    try {
      return await QrLoginApi.instance.profile(cookie);
    } on QrLoginException catch (e) {
      throw PassportException('登录凭证校验失败：${e.message}');
    }
  }
}
