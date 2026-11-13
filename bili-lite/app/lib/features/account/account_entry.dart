import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/auth_session.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import 'account_view.dart';

/// 账号入口卡片：登录态的紧凑展示 + 一键展开完整登录面板。
///
/// 为什么要单独做这个卡片：
///   之前账号卡片只藏在设置页最底部，用户在首页 / 「我的」页完全看不到，
///   常常以为「这应用没法登录」。现在把入口前置到「我的」页顶部和首页顶栏，
///   点一下就能展开完整的登录 / 授权码流程（内部复用 [AccountCard]）。
///
/// 状态与 [AccountCard] 完全一致，都来自 [AuthSession]：
///   未配置凭证 / 服务不可用 / 未登录 / 授权中 / 已登录。
class AccountEntry extends StatelessWidget {
  const AccountEntry({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return AnimatedBuilder(
      animation: authSession,
      builder: (context, _) {
        final s = authSession;
        return GlassPanel(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          onTap: () => _expand(context),
          child: Row(
            children: <Widget>[
              _avatar(s),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _title(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(s),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: sub, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.pink),
            ],
          ),
        );
      },
    );
  }

  Widget _avatar(AuthSession s) {
    final face = s.user?.face ?? '';
    final logged = s.signedIn;
    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.pink.withOpacity(0.16),
      backgroundImage:
          face.isNotEmpty ? NetworkImage(ApiConfig.image(face)) : null,
      child: face.isEmpty
          ? Icon(
              logged ? Icons.person_rounded : Icons.login_rounded,
              size: 21,
              color: AppColors.pink,
            )
          : null,
    );
  }

  String _title(AuthSession s) {
    switch (s.status) {
      case AuthStatus.signedIn:
        return s.user?.name ?? '已授权用户';
      case AuthStatus.authorizing:
        return '等待完成授权';
      case AuthStatus.unconfigured:
        return '登录入口未启用';
      case AuthStatus.unavailable:
        return '授权服务不可用';
      case AuthStatus.error:
        return '登录出错';
      default:
        return '登录 B 站账号';
    }
  }

  String _subtitle(AuthSession s) {
    switch (s.status) {
      case AuthStatus.signedIn:
        final t = s.tokens;
        if (t == null) return '已通过官方 OAuth 2.0 授权';
        return t.isExpired ? '登录已过期，点击重新授权' : '已通过官方 OAuth 2.0 授权';
      case AuthStatus.authorizing:
        return '已打开授权页，完成后回到此处粘贴一次性授权码';
      case AuthStatus.unconfigured:
        return '服务端未配置开放平台凭证，点这里查看配置清单';
      case AuthStatus.unavailable:
        return '连不上授权服务，请确认 BFF 已启动';
      case AuthStatus.error:
        return s.error.isEmpty ? '点击查看详情' : s.error;
      case AuthStatus.unknown:
        return '正在读取授权服务配置…';
      default:
        return '点这里展开完整登录流程';
    }
  }

  Future<void> _expand(BuildContext context) async {
    await showAccountSheet(context);
  }
}

/// 展开完整的账号 / 登录面板（底部弹层）。
///
/// 首页顶栏与「我的」页顶部都通过它进入登录流程，
/// 保证两处入口的行为完全一致，不会出现两个版本的登录界面。
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF161822) : const Color(0xFFF6F7FB),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const AccountCard(),
          ],
        ),
      ),
    );
  }
}
