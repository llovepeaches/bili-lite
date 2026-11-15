import 'package:flutter/foundation.dart' show Listenable;

import '../../state/globals.dart';
import '../../state/qr_session.dart';

/// 两路登录身份的统一视图。
///
/// B 站 Web 登录（[qrSession]，含扫码 / 密码 / 短信 / Cookie 四条通道）是主通道：
/// 不依赖任何服务端，装上就能用。
/// 官方 OAuth（[authSession]）是备用通道：需要自建持有 client_secret 的授权服务。
///
/// 优先级：**Web 登录优先**。原因是 `AuthSession.refreshConfig()` 会去探活 BFF，
/// 连不上就把状态压成 unavailable；独立安装包里 BFF 本来就不存在，不能让这次
/// 探活失败盖掉一个已经有效的扫码登录态。
class AccountIdentity {
  AccountIdentity._();

  /// 同时订阅两路状态，UI 用一个 AnimatedBuilder 即可。
  static Listenable get changes =>
      Listenable.merge(<Listenable>[qrSession, authSession]);

  static bool get signedIn => qrSession.signedIn || authSession.signedIn;

  static bool get viaQr => qrSession.signedIn;

  static String get name {
    if (qrSession.signedIn) {
      final n = qrSession.user?.name ?? '';
      return n.isEmpty ? 'B 站用户' : n;
    }
    if (authSession.signedIn) {
      final n = authSession.user?.name ?? '';
      return n.isEmpty ? '已授权用户' : n;
    }
    return '';
  }

  static String get face {
    if (qrSession.signedIn) return qrSession.user?.face ?? '';
    if (authSession.signedIn) return authSession.user?.face ?? '';
    return '';
  }

  /// 「扫码 / 账号密码 / 短信 / Cookie 登录」或「官方 OAuth 2.0」。
  static String get methodLabel =>
      qrSession.signedIn ? qrSession.method.label : '官方 OAuth 2.0 授权';

  /// 给账号入口卡片用的一行副标题。
  static String get subtitle {
    if (qrSession.signedIn) return '已通过${qrSession.method.label}';
    if (authSession.signedIn) return '已通过官方 OAuth 2.0 授权';
    return '点这里登录 B 站账号（扫码 / 密码 / 短信 / Cookie）';
  }
}
