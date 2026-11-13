import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../data/oauth_api.dart';

enum AuthStatus {
  /// 还没读到授权服务配置
  unknown,

  /// 服务端未配置官方开放平台凭证，登录入口停用（绝不伪造登录）
  unconfigured,

  /// 授权服务不可用
  unavailable,

  /// 已配置，未登录
  signedOut,

  /// 已打开官方授权页，等待回调 / 等待粘贴一次性码
  authorizing,

  /// 已登录
  signedIn,

  /// 出错
  error,
}

/// 官方 OAuth 2.0 登录态 + 本地持久化。
///
/// 数据边界（用户明确要求「本地存储数据」）：
///   存：access_token、refresh_token、过期时间、已授权 scope、openid / 昵称 / 头像。
///   不存：密码、Cookie、SESSDATA、bili_jct、client_secret、授权码 code。
///   位置：shared_preferences（Web → localStorage；原生 → 平台偏好），仅本机、不上传。
///
/// 注意：shared_preferences 不是硬件加密存储。真机发布建议把 token 迁到
/// iOS Keychain / Android Keystore；当前实现优先保证六端零原生插件可编译。
///
/// 跨端一致性：shared_preferences 2.1.x 在 Android / iOS / macOS / Windows /
/// Linux / Web 六端都有原生实现，本地登录态在所有端都能跨启动保留。
/// 只有在插件确实不可用时（[LocalStore.persistent] 为 false）才退化为
/// 「仅本次会话有效」，并由 UI 如实告知——不再按平台写死结论。
class AuthSession extends ChangeNotifier {
  AuthSession();

  static const String _kAccess = 'bili_lite_oauth_access_token';
  static const String _kRefresh = 'bili_lite_oauth_refresh_token';
  static const String _kExpires = 'bili_lite_oauth_expires_at';
  static const String _kScopes = 'bili_lite_oauth_scopes';
  static const String _kUser = 'bili_lite_oauth_user';

  final OAuthApi _api = OAuthApi.instance;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  OAuthConfigView? _config;
  OAuthConfigView? get config => _config;

  OAuthTokens? _tokens;
  OAuthTokens? get tokens => _tokens;

  BiliUser? _user;
  BiliUser? get user => _user;

  String _error = '';
  String get error => _error;

  bool _busy = false;
  bool get busy => _busy;

  /// 本地持久化是否可用。false 时登录态仅在本次会话有效。
  bool get storageAvailable => LocalStore.instance.persistent;

  bool get signedIn => _status == AuthStatus.signedIn && _tokens != null;

  bool get sandbox => _config?.sandbox == true;

  Future<void> init() async {
    await LocalStore.instance.init();
    await _restore();
    await refreshConfig();
  }

  // ------------------------------------------------------------------
  // 本地持久化
  // ------------------------------------------------------------------

  Future<void> _restore() async {
    final store = LocalStore.instance;
    final access = store.getString(_kAccess) ?? '';
    final refresh = store.getString(_kRefresh) ?? '';
    if (access.isEmpty) return;
    try {
      _tokens = OAuthTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: store.getInt(_kExpires) ?? 0,
        scopes: store.getStringList(_kScopes) ?? const <String>[],
      );
      final rawUser = store.getString(_kUser) ?? '';
      if (rawUser.isNotEmpty) {
        _user = BiliUser.fromJson(
            Map<String, dynamic>.from(json.decode(rawUser) as Map));
      }
    } catch (_) {
      _tokens = null;
      _user = null;
    }
  }

  Future<void> _persist() async {
    final store = LocalStore.instance;
    final t = _tokens;
    if (t == null) {
      await store.remove(_kAccess);
      await store.remove(_kRefresh);
      await store.remove(_kExpires);
      await store.remove(_kScopes);
      await store.remove(_kUser);
      return;
    }
    await store.setString(_kAccess, t.accessToken);
    await store.setString(_kRefresh, t.refreshToken);
    await store.setInt(_kExpires, t.expiresAt);
    await store.setStringList(_kScopes, t.scopes);
    final u = _user;
    await store.setString(_kUser, u == null ? '' : json.encode(u.toJson()));
  }

  // ------------------------------------------------------------------
  // 状态切换
  // ------------------------------------------------------------------

  void _set(AuthStatus next, {String error = ''}) {
    _status = next;
    _error = error;
    notifyListeners();
  }

  void _busyOn() {
    _busy = true;
    notifyListeners();
  }

  void _busyOff() {
    _busy = false;
    notifyListeners();
  }

  /// 重新读取授权服务配置；已登录且凭证临近过期时自动续期。
  Future<void> refreshConfig() async {
    _busyOn();
    try {
      _config = await _api.config();
      final cfg = _config!;
      if (!cfg.configured) {
        _set(AuthStatus.unconfigured);
        return;
      }
      final t = _tokens;
      if (t == null) {
        _set(AuthStatus.signedOut);
        return;
      }
      if (t.needsRefresh || t.isExpired) {
        try {
          await _applyTokens(await _api.refresh(t));
          _set(AuthStatus.signedIn);
        } catch (_) {
          // 续期失败保留本地凭证，让 UI 显示「已过期」并允许手动重试 / 重新登录
          _set(AuthStatus.signedIn,
              error: t.isExpired ? '登录已过期，请重新授权' : '自动续期失败，可手动重试');
        }
        return;
      }
      _set(AuthStatus.signedIn);
    } on OAuthException catch (e) {
      _set(AuthStatus.unavailable, error: e.message);
    } catch (e) {
      _set(AuthStatus.unavailable, error: '读取授权服务配置失败：$e');
    } finally {
      _busyOff();
    }
  }

  /// 发起官方授权：由 UI 用系统浏览器打开返回的 authorizeUrl。
  /// 客户端只拿到公开 URL 与 state，不接触 client_secret。
  Future<OAuthBegin?> beginLogin() async {
    _busyOn();
    try {
      final begun = await _api.begin(web: kIsWeb);
      _set(AuthStatus.authorizing);
      return begun;
    } on OAuthException catch (e) {
      _set(AuthStatus.error, error: e.message);
      return null;
    } catch (e) {
      _set(AuthStatus.error, error: '发起授权失败：$e');
      return null;
    } finally {
      _busyOff();
    }
  }

  /// 用回调带回的一次性 ticket 领取 token 并写入本地。
  /// 已经登录时（例如 Web 页面刷新重复携带 ticket）静默忽略重复领取错误。
  Future<void> completeWithTicket(String ticket) async {
    if (ticket.trim().isEmpty) return;
    _busyOn();
    try {
      final tokens = await _api.exchange(ticket);
      await _applyTokens(tokens, fetchUser: true);
      _set(AuthStatus.signedIn);
    } on OAuthException catch (e) {
      if (signedIn) {
        _set(AuthStatus.signedIn);
      } else {
        _set(AuthStatus.error, error: e.message);
      }
    } catch (e) {
      _set(AuthStatus.error, error: '领取凭证失败：$e');
    } finally {
      _busyOff();
    }
  }

  Future<void> _applyTokens(OAuthTokens tokens, {bool fetchUser = false}) async {
    _tokens = tokens;
    if (fetchUser || _user == null) {
      try {
        _user = await _api.me(tokens.accessToken);
      } catch (_) {
        // USER_INFO 可能未申请；登录态本身仍然有效，用占位展示
        _user = BiliUser(
          openid: '',
          name: '已授权用户',
          face: '',
          scopes: tokens.scopes,
          sandbox: sandbox,
        );
      }
    }
    await _persist();
  }

  Future<void> refreshNow() async {
    final t = _tokens;
    if (t == null) return;
    _busyOn();
    try {
      await _applyTokens(await _api.refresh(t));
      _set(AuthStatus.signedIn);
    } on OAuthException catch (e) {
      _set(AuthStatus.signedIn, error: '续期失败：${e.message}');
    } finally {
      _busyOff();
    }
  }

  Future<void> reloadProfile() async {
    final t = _tokens;
    if (t == null) return;
    _busyOn();
    try {
      _user = await _api.me(t.accessToken);
      await _persist();
      _set(AuthStatus.signedIn);
    } on OAuthException catch (e) {
      _set(AuthStatus.signedIn, error: '读取资料失败：${e.message}');
    } finally {
      _busyOff();
    }
  }

  /// 退出登录：清除本机全部凭证与资料。
  /// 如需在 B 站侧彻底解除授权，请到「B 站账号设置 → 隐私与安全 → 授权管理」操作。
  Future<void> signOut() async {
    _tokens = null;
    _user = null;
    await _persist();
    _set(_config?.configured == true
        ? AuthStatus.signedOut
        : AuthStatus.unconfigured);
  }

  void cancelAuthorizing() {
    if (_status == AuthStatus.authorizing) {
      _set(_config?.configured == true
          ? AuthStatus.signedOut
          : AuthStatus.unconfigured);
    }
  }
}
