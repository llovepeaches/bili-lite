import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/oauth_launcher.dart';
import '../../state/auth_session.dart';
import '../../state/globals.dart';
import '../../widgets/confirm_dialog.dart';

/// 账号卡片的动作控制器。
///
/// 重构前登录 / 退出 / 授权码粘贴这些流程全部写在 `account_card.dart` 的
/// State 里，导致 400 多行的视图文件里混杂着异步流程与错误处理。
///
/// 这里把「做什么」抽到 controller，「长什么样」留在 view：
///   * `beginLogin()` —— 走官方 OAuth 授权码流程
///   * `submitTicket()` / `cancelAuthorizing()` —— 桌面 / 手机端的一次性授权码
///   * `signOut()` —— 退出登录（带二次确认）
///   * `mask()` —— openid 等敏感串的掩码展示
///
/// 约定：需要弹窗的动作由调用方传入 `BuildContext`，controller 自身不持有
/// 任何 Widget 引用，避免生命周期泄漏。
class AccountController extends ChangeNotifier {
  final TextEditingController ticket = TextEditingController();

  AuthSession get session => authSession;

  /// 打开官方授权页。返回 false 表示没能打开（调用方负责提示）。
  Future<bool> beginLogin() async {
    final begun = await authSession.beginLogin();
    if (begun == null) return false;
    try {
      await openAuthorizeUrl(begun.authorizeUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> submitTicket() async {
    final code = ticket.text.trim();
    if (code.isEmpty) return;
    await authSession.completeWithTicket(code);
  }

  void cancelAuthorizing() {
    authSession.cancelAuthorizing();
  }

  /// 退出登录。`context` 仅用于弹出二次确认对话框。
  Future<bool> signOut(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '退出 B 站账号？',
      message: '将删除本机保存的 access_token、refresh_token 与账号资料，不可撤销。'
          '这不会解除 B 站侧的授权，如需彻底解除请到 B 站账号设置里的授权管理操作。',
      confirmLabel: '退出登录',
    );
    if (!ok) return false;
    await authSession.signOut();
    return true;
  }

  /// 掩码展示敏感标识，只保留首尾各 4 位。
  static String mask(String raw) {
    if (raw.isEmpty) return '—';
    if (raw.length <= 8) return raw;
    return '${raw.substring(0, 4)}…${raw.substring(raw.length - 4)}';
  }

  /// 授权服务地址（供「授权服务」一行展示）。
  static String get oauthService => ApiConfig.oauthDisplayBase;

  @override
  void dispose() {
    ticket.dispose();
    super.dispose();
  }
}
