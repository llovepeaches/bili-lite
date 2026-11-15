import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../data/bili_direct.dart';
import '../data/passport_api.dart';
import '../data/qr_login_api.dart';

enum QrStatus { signedOut, generating, waiting, scanned, expired, signedIn, error }

/// 拿到 B 站 Web 登录 Cookie 的具体通道。
///
/// 扫码 / 账号密码 / 短信验证码 / 直接粘贴 Cookie 的产物都是同一份 Cookie，
/// 因此共用 [QrSession] 这一份登录态，只在这里记录「从哪条路进来的」，
/// 供账号卡片如实展示，避免再引入多套互相打架的身份状态。
enum LoginMethod { qr, password, sms, cookie }

extension LoginMethodLabel on LoginMethod {
  String get label {
    switch (this) {
      case LoginMethod.qr:
        return '扫码登录';
      case LoginMethod.password:
        return '账号密码登录';
      case LoginMethod.sms:
        return '短信验证码登录';
      case LoginMethod.cookie:
        return 'Cookie 登录';
    }
  }
}

/// B 站 Web 登录态（独立于官方 OAuth 的 [AuthSession]）。
///
/// 扫码 / 账号密码 / 短信验证码 / 直接粘贴 Cookie 四条通道的产物都是
/// **同一份 B 站 Web 登录 Cookie**，因此统一由本 Session 管理，只额外记录
/// [LoginMethod] 用于展示。这样身份展示、退出登录、数据边界只需一套实现。
///
/// 为什么独立于官方 OAuth：OAuth 链路依赖「授权服务端持有 client_secret」，
/// 独立安装包里没有这个服务，导致 `AuthSession.refreshConfig()` 探活失败后
/// 把整个账号状态压成 unavailable。Web 登录不需要任何服务端，必须能独立成立，
/// 不能被 BFF 是否在线影响。UI 层按「Web 登录优先、OAuth 兜底」合并两路身份。
///
/// 数据边界（与 OAuth 不同，必须如实告知用户）：
///   存：B 站 Web 登录 Cookie（SESSDATA / bili_jct / DedeUserID 等）、mid / 昵称 / 头像。
///   不存：密码、验证码、client_secret；Cookie 不上传任何第三方，只发往 bilibili.com。
///   位置：shared_preferences（Web → localStorage），**不是硬件加密存储**。
class QrSession extends ChangeNotifier {
  QrSession();

  static const String _kCookie = 'bili_lite_qr_cookie';
  static const String _kUser = 'bili_lite_qr_user';
  static const String _kMethod = 'bili_lite_qr_login_method';

  static const Duration pollInterval = Duration(seconds: 2);

  final QrLoginApi _api = QrLoginApi.instance;

  QrStatus _status = QrStatus.signedOut;
  QrStatus get status => _status;

  String _message = '';
  String get message => _message;

  QrChallenge? _challenge;
  QrChallenge? get challenge => _challenge;

  QrUser? _user;
  QrUser? get user => _user;

  String _cookie = '';
  String get cookie => _cookie;

  LoginMethod _method = LoginMethod.qr;
  LoginMethod get method => _method;

  Timer? _timer;
  bool _polling = false;

  bool get signedIn => _status == QrStatus.signedIn && _cookie.isNotEmpty;
  bool get busy => _status == QrStatus.generating;
  bool get active => _timer != null;

  Future<void> init() async {
    await LocalStore.instance.init();
    final store = LocalStore.instance;
    _cookie = store.getString(_kCookie) ?? '';
    _method = _methodFromString(store.getString(_kMethod) ?? '');
    final rawUser = store.getString(_kUser) ?? '';
    if (rawUser.isNotEmpty) {
      try {
        _user = QrUser.fromJson(
            Map<String, dynamic>.from(json.decode(rawUser) as Map));
      } catch (_) {
        _user = null;
      }
    }
    // 恢复登录态时同步给原生直连通道，否则重启后请求仍按访客身份发出。
    BiliDirect.userCookie = _cookie;
    if (_cookie.isNotEmpty) {
      _set(QrStatus.signedIn, '已登录');
    } else {
      _set(QrStatus.signedOut, '');
    }
  }

  /// 不依赖增强枚举的 `.name`（Dart 2.17 兼容）。
  static LoginMethod _methodFromString(String raw) {
    switch (raw) {
      case 'password':
        return LoginMethod.password;
      case 'sms':
        return LoginMethod.sms;
      case 'cookie':
        return LoginMethod.cookie;
      default:
        return LoginMethod.qr;
    }
  }

  static String _methodToString(LoginMethod method) {
    switch (method) {
      case LoginMethod.password:
        return 'password';
      case LoginMethod.sms:
        return 'sms';
      case LoginMethod.cookie:
        return 'cookie';
      default:
        return 'qr';
    }
  }

  void _set(QrStatus next, String message) {
    _status = next;
    _message = message;
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _polling = false;
  }

  /// 生成二维码并开始轮询。重复调用会先取消上一轮。
  Future<void> start() async {
    _stopTimer();
    _set(QrStatus.generating, '正在向 B 站申请二维码…');
    try {
      final challenge = await _api.generate();
      _challenge = challenge;
      _set(QrStatus.waiting, '请用 B 站 App 扫描二维码');
      _timer = Timer.periodic(pollInterval, (_) => _tick());
    } on QrLoginException catch (e) {
      _set(QrStatus.error, e.message);
    } catch (e) {
      _set(QrStatus.error, '获取二维码失败：$e');
    }
  }

  Future<void> _tick() async {
    final challenge = _challenge;
    if (challenge == null || _polling || signedIn) return;
    if (challenge.isExpired) {
      _stopTimer();
      _set(QrStatus.expired, '二维码已失效，请点「刷新二维码」');
      return;
    }
    _polling = true;
    try {
      final result = await _api.poll(challenge.key);
      switch (result.state) {
        case QrPollState.waiting:
          _set(QrStatus.waiting, result.message);
          break;
        case QrPollState.scanned:
          _set(QrStatus.scanned, result.message);
          break;
        case QrPollState.expired:
          _stopTimer();
          _set(QrStatus.expired, result.message);
          break;
        case QrPollState.success:
          _stopTimer();
          await _complete(result.cookie, LoginMethod.qr);
          break;
        case QrPollState.failed:
          _stopTimer();
          _set(QrStatus.error, result.message);
          break;
      }
    } on QrLoginException catch (e) {
      // 单次网络抖动不终止整个流程，但连续失败要让用户看得到。
      _set(_status, e.message);
    } catch (e) {
      _set(_status, '轮询扫码状态失败：$e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _complete(String cookie, LoginMethod method) async {
    if (cookie.isEmpty) {
      _set(QrStatus.error, '登录成功但没拿到可用凭证，请重新扫码');
      return;
    }
    _cookie = cookie;
    _method = method;
    try {
      _user = await _api.profile(cookie);
    } on QrLoginException catch (_) {
      // 资料接口有风控时登录态本身仍可能有效，用占位展示，不让登录白做。
      _user = const QrUser(
          mid: '', name: 'B 站用户', face: '', vipLabel: '');
    } catch (_) {
      _user = const QrUser(
          mid: '', name: 'B 站用户', face: '', vipLabel: '');
    }
    await _persist();
    _set(QrStatus.signedIn, '登录成功');
  }

  /// 非扫码通道（账号密码 / 短信 / 直接粘贴 Cookie）的统一落地入口。
  ///
  /// 与 [_complete] 的区别：**严格校验**。扫码拿到的 Cookie 由 B 站直接下发，
  /// 可以容忍 nav 接口风控；用户手工粘贴的 Cookie 则必须先经 nav 确认有效，
  /// 否则绝不写入本地、绝不显示「已登录」——避免留下半套凭证却查不出原因。
  /// 校验通过后才复用同一套持久化与账号资料，登录态与扫码完全等价。
  ///
  /// 抛出 [PassportException] 让 UI 展示具体原因。
  Future<void> applyCookie(String cookie, LoginMethod method) async {
    _set(QrStatus.generating, '正在校验登录凭证…');
    try {
      final user = await PassportApi.instance.verifyCookie(cookie);
      _cookie = cookie;
      _user = user;
      _method = method;
      await _persist();
      _set(QrStatus.signedIn, '登录成功（${method.label}）');
    } catch (e) {
      _set(QrStatus.error, '登录凭证无效：$e');
      rethrow;
    }
  }

  Future<void> _persist() async {
    // 四条登录通道（扫码 / 密码 / 短信 / 粘贴 Cookie）与退出登录都经过这里，
    // 在这一处同步登录凭证，原生直连请求就能随登录态实时切换。
    BiliDirect.userCookie = _cookie;
    final store = LocalStore.instance;
    if (_cookie.isEmpty) {
      await store.remove(_kCookie);
      await store.remove(_kUser);
      await store.remove(_kMethod);
      return;
    }
    await store.setString(_kCookie, _cookie);
    await store.setString(_kMethod, _methodToString(_method));
    final u = _user;
    await store.setString(_kUser, u == null ? '' : json.encode(u.toJson()));
  }

  /// 重新拉取资料（例如 B 站昵称改了）。
  Future<void> reloadProfile() async {
    if (!signedIn) return;
    try {
      _user = await _api.profile(_cookie);
      await _persist();
      _set(QrStatus.signedIn, '资料已更新');
    } on QrLoginException catch (e) {
      _set(QrStatus.signedIn, '读取资料失败：${e.message}');
    }
  }

  /// 退出登录：删除本机 Cookie 与资料。
  Future<void> signOut() async {
    _stopTimer();
    _cookie = '';
    _user = null;
    _challenge = null;
    _method = LoginMethod.qr;
    await _persist();
    _set(QrStatus.signedOut, '');
  }

  /// 关闭扫码弹层时停掉轮询，避免后台一直打 B 站接口。
  void cancel() {
    if (signedIn) return;
    final wasActive = _timer != null;
    _stopTimer();
    if (wasActive && (_status == QrStatus.waiting ||
        _status == QrStatus.scanned)) {
      _set(QrStatus.signedOut, '');
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
