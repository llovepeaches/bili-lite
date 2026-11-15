import 'dart:convert';

import 'package:bililite/core/storage.dart';
import 'package:bililite/data/passport_api.dart';
import 'package:bililite/data/qr_login_api.dart';
import 'package:bililite/state/qr_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 一组固定生成的 1024-bit toy RSA 密钥（仅用于测试，不是任何真实凭证）。
/// 用私钥 d 能把公钥加密结果还原，才算真正验证了 PKCS#1 v1.5 填充，
/// 而不是只测「函数没抛异常」。
const String _toyPem = '''-----BEGIN PUBLIC KEY-----
MIGeMA0GCSqGSIb3DQEBAQUAA4GMADCBiAKBgH5PcYqV6/IKfLWVKCBJdUBGILYY
sonCcgFN7e5s0zT/XjuIF+gfk7r/5mgHTVbMhBS6F4+kjxg2kQGmElTtNO/iZMuX
xcZqNqjxm+MEqV+i22aTGPFuUrKeX0z/1SQYLpKw/c2likpqrx/OmVjMzqgmAxqd
4yYsjpSH+Y7+vQJVAgMBAAE=
-----END PUBLIC KEY-----''';

const String _toyN =
    '7e4f718a95ebf20a7cb59528204975404620b618b289c272014dedee6cd334ff5e3'
    'b8817e81f93baffe668074d56cc8414ba178fa48f18369101a61254ed34efe264cb9'
    '7c5c66a36a8f19be304a95fa2db669318f16e52b29e5f4cffd524182e92b0fdcda'
    '58a4a6aaf1fce9958cccea826031a9de3262c8e9487f98efebd0255';

const String _toyD =
    '3173f3355a4b5da18380289ce43f3e7be2b90df28f7c6637f290cb562d1f68418f'
    '6869794ab58a468dc86cf466f053f46695118278e0598f8ba88497eace508a0a5174'
    'e28644e307ff5ce057efeb899655f56cdf96b07b74bbe0b0095710f3bb6f993302e0'
    '7b1fe6736c8500d77273d3b287a5000d294c1c80c46a7e1dab7da5';

BigInt _bytesToBigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  return value;
}

List<int> _bigIntToBytes(BigInt value, int length) {
  final hex = value.toRadixString(16).padLeft(length * 2, '0');
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

class _StubClient extends http.BaseClient {
  _StubClient(this._handler);
  final http.StreamedResponse Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _handler(request);
}

http.StreamedResponse _json(Object payload, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode(json.encode(payload)),
      ]),
      status,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

const String _loginUrl = 'https://www.bilibili.com/'
    '?SESSDATA=abc%2Cdef&bili_jct=jct99&DedeUserID=123';

Map<String, dynamic> _ok(Map<String, dynamic> data) => <String, dynamic>{
      'code': 0,
      'message': 'ok',
      'data': data,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  tearDown(() {
    // 单例被注入过 stub，必须还原，避免污染其他测试文件之外的调用方。
    PassportApi.instance.debugClient = http.Client();
    QrLoginApi.instance.debugClient = http.Client();
  });

  group('Cookie 规范化', () {
    test('空串直接报错', () {
      expect(
        () => PassportApi.normalizeCookie('  '),
        throwsA(isA<PassportException>()
            .having((e) => e.message, 'message', contains('请先粘贴'))),
      );
    });

    test('缺 SESSDATA 或 bili_jct 时拒绝写入半套凭证', () {
      for (final raw in <String>[
        'SESSDATA=abc',
        'bili_jct=xyz',
        'DedeUserID=1; sid=s',
        'SESSDATA=abc; DedeUserID=1',
      ]) {
        expect(
          () => PassportApi.normalizeCookie(raw),
          throwsA(isA<PassportException>().having((e) => e.message, 'message',
              contains('必须同时包含 SESSDATA 和 bili_jct'))),
          reason: raw,
        );
      }
    });

    test('DevTools 整串：只保留白名单字段并按固定顺序输出', () {
      final out = PassportApi.normalizeCookie(
        'SESSDATA=a%2Cb; bili_jct=bb; DedeUserID=42; '
        'DedeUserID__ckMd5=md5; sid=s1; buvid3=b3; '
        'other_field=should_be_dropped; Path=/',
      );
      expect(out, contains('SESSDATA=a%2Cb'));
      expect(out, contains('bili_jct=bb'));
      expect(out, contains('DedeUserID=42'));
      expect(out, isNot(contains('other_field')));
      expect(out, isNot(contains('Path')));
      // 百分号编码必须原样保留，不能被 URL 解码成逗号 / 星号。
      expect(out, contains('%2C'));
    });

    test('URL query（& 分隔）与换行粘贴同样可解析', () {
      final out = PassportApi.normalizeCookie(
        'SESSDATA=aa%2Azz&bili_jct=jj&DedeUserID=7\n'
        'DedeUserID__ckMd5=mm',
      );
      expect(out, contains('SESSDATA=aa%2Azz'));
      expect(out, contains('bili_jct=jj'));
      expect(out, contains('DedeUserID__ckMd5=mm'));
    });

    test('只填两个必填字段的极简形式可用', () {
      final out = PassportApi.normalizeCookie('bili_jct=j; SESSDATA=s');
      expect(out, 'SESSDATA=s; bili_jct=j');
    });
  });

  group('纯 Dart RSA（PKCS#1 v1.5）', () {
    test('满长度填充可被对应私钥逐字节还原', () {
      const int modulusBytes = 128;
      final message = utf8.encode('hash123secret');
      final padding = List<int>.filled(
          modulusBytes - message.length - 3, 0x41); // 全非零
      final b64 = PassportApi.encryptWithPaddingForTest(
          _toyPem, message, padding);
      final cipher = base64.decode(b64);
      expect(cipher.length, modulusBytes);

      final n = BigInt.parse(_toyN, radix: 16);
      final d = BigInt.parse(_toyD, radix: 16);
      final recovered =
          _bigIntToBytes(_bytesToBigInt(cipher).modPow(d, n), modulusBytes);
      expect(recovered[0], 0x00);
      expect(recovered[1], 0x02);
      expect(recovered.sublist(2, 2 + padding.length), padding);
      expect(recovered[2 + padding.length], 0x00);
      expect(recovered.sublist(recovered.length - message.length), message);
    });

    test('encryptPassword 用安全随机填充、明文不出现在密文里且每次不同', () {
      final first = PassportApi.encryptPassword('hashabc', _toyPem, 'p@ssw0rd');
      final second = PassportApi.encryptPassword('hashabc', _toyPem, 'p@ssw0rd');
      expect(first, isNot(second));

      final cipher = base64.decode(first);
      expect(cipher.length, 128);
      final n = BigInt.parse(_toyN, radix: 16);
      final d = BigInt.parse(_toyD, radix: 16);
      final recovered =
          _bigIntToBytes(_bytesToBigInt(cipher).modPow(d, n), 128);
      expect(recovered[0], 0x00);
      expect(recovered[1], 0x02);

      // padding 段绝不能出现 0x00，分隔符是第一个零字节。
      final sep = recovered.sublist(2).indexOf(0) + 2;
      expect(sep, greaterThanOrEqualTo(10));
      expect(recovered.sublist(2, sep).every((b) => b != 0), isTrue);
      expect(utf8.decode(recovered.sublist(sep + 1)), 'hashabcp@ssw0rd');
    });

    test('非法 PEM 抛 PassportException 而不是格式异常', () {
      expect(
        () => PassportApi.encryptPassword('h', 'not-a-pem', 'p'),
        throwsA(isA<PassportException>()),
      );
    });
  });

  group('上游接口链路与错误码', () {
    test('fetchKey 解析 hash 与 RSA 公钥，且直连 B 站登录域', () {
      late http.BaseRequest seen;
      PassportApi.instance.debugClient = _StubClient((req) {
        seen = req;
        return _json(_ok(<String, dynamic>{
          'hash': 'h-1',
          'key': _toyPem,
        }));
      });
      return PassportApi.instance.fetchKey().then((key) {
        expect(key.hash, 'h-1');
        expect(key.pem, contains('BEGIN PUBLIC KEY'));
        expect(seen.url.host, 'passport.bilibili.com');
        expect(seen.url.path, '/x/passport-login/web/key');
      });
    });

    test('上游 -105 映射为人机验证提示并标记 needsCaptcha', () async {
      PassportApi.instance.debugClient = _StubClient(
        (_) => _json(<String, dynamic>{
          'code': -105,
          'message': '验证码错误',
          'data': <String, dynamic>{},
        }),
      );
      try {
        await PassportApi.instance.fetchKey();
        fail('应当抛出 PassportException');
      } on PassportException catch (e) {
        expect(e.code, -105);
        expect(e.needsCaptcha, isTrue);
        expect(e.message, contains('人机验证'));
        expect(e.message, contains('Cookie 登录'));
      }
    });

    test('fetchCaptcha 解析极验 gt / challenge / token', () async {
      PassportApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{
          'type': 'geetest',
          'token': 'tok-9',
          'geetest': <String, dynamic>{
            'gt': 'gt-9',
            'challenge': 'ch-9',
          },
        })),
      );
      final c = await PassportApi.instance.fetchCaptcha();
      expect(c.isGeetest, isTrue);
      expect(c.token, 'tok-9');
      expect(c.gt, 'gt-9');
      expect(c.challenge, 'ch-9');
    });

    test('passwordLogin 提交的是 RSA 密文，返回合成后的 Cookie', () async {
      late http.BaseRequest seen;
      PassportApi.instance.debugClient = _StubClient((req) {
        seen = req;
        return _json(_ok(<String, dynamic>{'url': _loginUrl}));
      });
      final encrypted =
          PassportApi.encryptPassword('h', _toyPem, 'plain-secret');
      final cookie = await PassportApi.instance.passwordLogin(
        username: 'user@example.com',
        encryptedPassword: encrypted,
      );
      expect(cookie, contains('SESSDATA=abc%2Cdef'));
      expect(cookie, contains('bili_jct=jct99'));
      expect(seen.url.path, '/x/passport-login/web/login');
      final fields = (seen as http.Request).bodyFields;
      expect(fields['username'], 'user@example.com');
      expect(fields['password'], encrypted);
      expect(fields['password'], isNot(contains('plain-secret')));
    });

    test('登录成功但没拿到凭证时明确失败，不假装登录成功', () async {
      PassportApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{})),
      );
      expect(
        () => PassportApi.instance.passwordLogin(
            username: 'u', encryptedPassword: 'enc'),
        throwsA(isA<PassportException>().having((e) => e.message, 'message',
            contains('未返回可用登录凭证'))),
      );
    });

    test('sendSmsCode 返回 captcha_key，缺失时报错', () async {
      PassportApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{'captcha_key': 'ck-77'})),
      );
      final result = await PassportApi.instance.sendSmsCode(tel: '13800138000');
      expect(result.captchaKey, 'ck-77');

      PassportApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{})),
      );
      expect(
        () => PassportApi.instance.sendSmsCode(tel: '13800138000'),
        throwsA(isA<PassportException>()),
      );
    });

    test('smsLogin 带上 captcha_key 并返回 Cookie', () async {
      late http.BaseRequest seen;
      PassportApi.instance.debugClient = _StubClient((req) {
        seen = req;
        return _json(_ok(<String, dynamic>{'url': _loginUrl}));
      });
      final cookie = await PassportApi.instance.smsLogin(
        tel: '13800138000',
        code: '123456',
        captchaKey: 'ck-1',
      );
      expect(cookie, contains('SESSDATA='));
      final fields = (seen as http.Request).bodyFields;
      expect(fields['captcha_key'], 'ck-1');
      expect(fields['code'], '123456');
      expect(seen.url.path, '/x/passport-login/web/login/sms');
    });
  });

  group('QrSession 统一登录态', () {
    /// 每个用例都从「已清空本机凭证」开始，不依赖测试执行顺序。
    Future<QrSession> fresh() async {
      final s = QrSession();
      await s.init();
      await s.signOut();
      return s;
    }

    test('LoginMethod 四条通道的标签完整', () {
      expect(LoginMethod.values.length, 4);
      expect(LoginMethod.qr.label, '扫码登录');
      expect(LoginMethod.password.label, '账号密码登录');
      expect(LoginMethod.sms.label, '短信验证码登录');
      expect(LoginMethod.cookie.label, 'Cookie 登录');
    });

    test('Cookie 登录：nav 校验通过后才写入本机并记录登录方式', () async {
      final s = await fresh();
      QrLoginApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{
          'isLogin': true,
          'mid': 42,
          'uname': '测试用户',
          'face': 'https://example.com/face.jpg',
          'vipStatus': 1,
        })),
      );
      await s.applyCookie('SESSDATA=a; bili_jct=b', LoginMethod.cookie);
      expect(s.signedIn, isTrue);
      expect(s.method, LoginMethod.cookie);
      expect(s.cookie, 'SESSDATA=a; bili_jct=b');
      expect(s.user?.name, '测试用户');
      expect(s.user?.vipLabel, '大会员');

      // 新实例从本机恢复，登录方式不能退化回「扫码」。
      final restored = QrSession();
      await restored.init();
      expect(restored.signedIn, isTrue);
      expect(restored.method, LoginMethod.cookie);
      await restored.signOut();
    });

    test('Cookie 登录：nav 判定无效时绝不落半套凭证', () async {
      final s = await fresh();
      QrLoginApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{'isLogin': false})),
      );
      await expectLater(
        s.applyCookie('SESSDATA=bad; bili_jct=bad', LoginMethod.cookie),
        throwsA(isA<PassportException>().having((e) => e.message, 'message',
            contains('登录凭证校验失败'))),
      );
      expect(s.signedIn, isFalse);
      expect(s.cookie, isEmpty);
      expect(s.status, QrStatus.error);
    });

    test('退出登录清空凭证并把登录方式重置为扫码', () async {
      final s = await fresh();
      QrLoginApi.instance.debugClient = _StubClient(
        (_) => _json(_ok(<String, dynamic>{
          'isLogin': true,
          'mid': 1,
          'uname': 'A',
          'face': '',
          'vipStatus': 0,
        })),
      );
      await s.applyCookie('SESSDATA=a; bili_jct=b', LoginMethod.sms);
      expect(s.method, LoginMethod.sms);
      await s.signOut();
      expect(s.cookie, isEmpty);
      expect(s.user, isNull);
      expect(s.method, LoginMethod.qr);
      expect(s.signedIn, isFalse);
    });
  });
}
