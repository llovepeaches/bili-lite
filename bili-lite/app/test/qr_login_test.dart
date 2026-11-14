import 'package:flutter_test/flutter_test.dart';
import 'package:bililite/core/server_config.dart';
import 'package:bililite/data/qr_login_api.dart';

void main() {
  group('扫码登录 Cookie 合成', () {
    test('从 Set-Cookie 多段里提取需要的字段', () {
      final cookie = QrLoginApi.buildCookie(
        <String, String>{
          'set-cookie': 'SESSDATA=abc%2Cdef; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; '
              'HttpOnly, bili_jct=xyz123; Path=/, '
              'DedeUserID=456789; Path=/, '
              'DedeUserID__ckMd5=hashhash; Path=/, '
              'sid=session1; Path=/, '
              'buvid3=nope; Path=/',
        },
        '',
      );
      expect(cookie, contains('SESSDATA=abc%2Cdef'));
      expect(cookie, contains('bili_jct=xyz123'));
      expect(cookie, contains('DedeUserID=456789'));
      expect(cookie, contains('DedeUserID__ckMd5=hashhash'));
      expect(cookie, contains('sid=session1'));
      expect(cookie, isNot(contains('Expires')));
      expect(cookie, isNot(contains('Path')));
    });

    test('回调 URL 参数优先级高于 Set-Cookie', () {
      final cookie = QrLoginApi.buildCookie(
        <String, String>{'set-cookie': 'SESSDATA=old; Path=/, bili_jct=old; Path=/'},
        'https://www.bilibili.com/?SESSDATA=new&bili_jct=newjct'
        '&DedeUserID=9988&DedeUserID__ckMd5=md5x&sid=s2',
      );
      expect(cookie, contains('SESSDATA=new'));
      expect(cookie, contains('bili_jct=newjct'));
      expect(cookie, contains('DedeUserID=9988'));
      expect(cookie, isNot(contains('SESSDATA=old')));
    });

    test('缺 SESSDATA 或 bili_jct 时不返回半套凭证', () {
      expect(
        QrLoginApi.buildCookie(
            <String, String>{'set-cookie': 'SESSDATA=only; Path=/'}, ''),
        isEmpty,
      );
      expect(
        QrLoginApi.buildCookie(
            <String, String>{'set-cookie': 'bili_jct=only; Path=/'}, ''),
        isEmpty,
      );
      expect(QrLoginApi.buildCookie(<String, String>{}, ''), isEmpty);
    });

    test('URL 里的值带特殊字符也能保留', () {
      final cookie = QrLoginApi.buildCookie(
        <String, String>{},
        'https://www.bilibili.com/?SESSDATA=a%2Cb%2Adef'
        '&bili_jct=bb77&DedeUserID=12',
      );
      expect(cookie, contains('SESSDATA=a%2Cb%2Adef'));
      expect(cookie, contains('bili_jct=bb77'));
    });
  });

  group('二维码有效期', () {
    test('刚生成不过期', () {
      expect(
        QrChallenge(url: 'u', key: 'k', createdAt: DateTime.now()).isExpired,
        isFalse,
      );
    });

    test('超过 170 秒判定过期', () {
      final old = DateTime.now().subtract(const Duration(seconds: 175));
      expect(
        QrChallenge(url: 'u', key: 'k', createdAt: old).isExpired,
        isTrue,
      );
    });
  });

  group('授权服务地址校验', () {
    test('空值表示恢复默认，合法', () {
      expect(ServerConfig.validate(''), isNull);
      expect(ServerConfig.validate('   '), isNull);
    });

    test('局域网 IP / 域名合法', () {
      expect(ServerConfig.validate('http://192.168.1.10:8787'), isNull);
      expect(ServerConfig.validate('192.168.1.10:8787'), isNull);
      expect(ServerConfig.validate('https://auth.example.com'), isNull);
    });

    test('非法协议被拒', () {
      expect(ServerConfig.validate('ftp://1.2.3.4'), isNotNull);
      expect(ServerConfig.validate('://bad'), isNotNull);
    });
  });

  group('轮询状态码映射', () {
    // 通过 poll 的响应解析间接验证；这里只锁定常量语义，避免上层把
    // 86101 / 86090 / 86038 当失败处理。
    test('业务码含义有文档注释可查', () {
      expect(QrPollState.values.length, 5);
      expect(QrPollState.waiting.index, 0);
      expect(QrPollState.success.index, 3);
    });
  });
}
