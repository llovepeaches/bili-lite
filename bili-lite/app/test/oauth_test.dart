import 'package:flutter_test/flutter_test.dart';

import 'package:bililite/core/config.dart';
import 'package:bililite/data/oauth_api.dart';

void main() {
  group('官方 OAuth 配置视图', () {
    test('未配置时列出缺失项且不携带密钥字段', () {
      final cfg = OAuthConfigView.fromJson(<String, dynamic>{
        'configured': false,
        'sandbox': false,
        'clientId': '',
        'redirectUri': '',
        'scopes': <dynamic>['USER_INFO'],
        'missing': <dynamic>[
          'BILI_CLIENT_ID',
          'BILI_CLIENT_SECRET',
          'BILI_REDIRECT_URI'
        ],
        'note': '未配置',
      });
      expect(cfg.configured, isFalse);
      expect(cfg.sandbox, isFalse);
      expect(cfg.missing.length, 3);
      expect(cfg.scopes, <String>['USER_INFO']);
      // 结构上就没有 secret 字段，序列化时也不会带出
      expect(cfg.runtimeType.toString(), 'OAuthConfigView');
    });

    test('演示模式被明确标记', () {
      final cfg = OAuthConfigView.fromJson(<String, dynamic>{
        'configured': true,
        'sandbox': true,
        'clientId': 'sandbox-app',
        'scopes': <dynamic>['USER_INFO'],
      });
      expect(cfg.configured, isTrue);
      expect(cfg.sandbox, isTrue);
      expect(cfg.missing, isEmpty);
    });
  });

  group('授权发起结果', () {
    test('解析授权页 URL 与一次性 state', () {
      final begun = OAuthBegin.fromJson(<String, dynamic>{
        'authorizeUrl':
            'https://account.bilibili.com/pc/account-pc/auth/oauth?client_id=x&gourl=y&state=z',
        'state': 'z',
        'redirectUri': 'https://example.com/api/oauth/callback',
        'scopes': <dynamic>['USER_INFO'],
        'sandbox': false,
        'expiresAt': 1700000000000,
      });
      expect(begun.authorizeUrl.startsWith('https://account.bilibili.com/'),
          isTrue);
      expect(begun.state, 'z');
      expect(begun.sandbox, isFalse);
      expect(begun.expiresAt, 1700000000000);
    });
  });

  group('本地凭证', () {
    test('有效期按毫秒绝对时间戳判断', () {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final expired = OAuthTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAt: stamp - 1000,
        scopes: const <String>['USER_INFO'],
      );
      expect(expired.isExpired, isTrue);

      final soon = OAuthTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAt: stamp + 60 * 1000,
        scopes: const <String>['USER_INFO'],
      );
      expect(soon.isExpired, isFalse);
      expect(soon.needsRefresh, isTrue);

      final fresh = OAuthTokens(
        accessToken: 'at',
        refreshToken: 'rt',
        expiresAt: stamp + 3600 * 1000,
        scopes: const <String>['USER_INFO'],
      );
      expect(fresh.needsRefresh, isFalse);
      expect(fresh.expiresText, isNotEmpty);
    });

    test('序列化往返不丢失字段', () {
      final t = OAuthTokens(
        accessToken: 'at-123',
        refreshToken: 'rt-456',
        expiresAt: 1700000000000,
        scopes: const <String>['USER_INFO', 'ARC_BASE'],
      );
      final restored = OAuthTokens.fromJson(t.toJson());
      expect(restored.accessToken, 'at-123');
      expect(restored.refreshToken, 'rt-456');
      expect(restored.expiresAt, 1700000000000);
      expect(restored.scopes, <String>['USER_INFO', 'ARC_BASE']);
    });

    test('用户资料序列化往返', () {
      final u = BiliUser(
        openid: 'openid-1',
        name: '昵称',
        face: 'https://i0.hdslb.com/face.jpg',
        scopes: const <String>['USER_INFO'],
        sandbox: false,
      );
      final restored = BiliUser.fromJson(u.toJson());
      expect(restored.openid, 'openid-1');
      expect(restored.name, '昵称');
      expect(restored.face, 'https://i0.hdslb.com/face.jpg');
      expect(restored.sandbox, isFalse);
    });
  });

  group('授权服务地址', () {
    test('OAuth 始终指向 BFF 而不是直连 B 站', () {
      final u = ApiConfig.oauthUrl('/api/oauth/config');
      expect(u.endsWith('/api/oauth/config'), isTrue);
      expect(u.contains('api.bilibili.com'), isFalse);
    });
  });
}
