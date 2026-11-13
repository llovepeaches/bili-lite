import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/oauth_launcher.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/auth_session.dart';
import '../../state/globals.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';

/// 设置页里的「B 站账号」卡片。
///
/// 对应官方 OAuth 2.0 授权码流程：授权在 B 站官方页面完成，BFF 持有
/// client_secret 换取 token，客户端领取后按用户要求持久化到本机。
/// 没有开放平台凭证时明确显示「未配置」，绝不伪造登录入口。
class AccountCard extends StatefulWidget {
  const AccountCard({Key? key}) : super(key: key);

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final TextEditingController _ticket = TextEditingController();

  @override
  void dispose() {
    _ticket.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final begun = await authSession.beginLogin();
    if (begun == null) return;
    try {
      await openAuthorizeUrl(begun.authorizeUrl);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无法打开授权页，请检查浏览器或网络'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(
      context,
      title: '退出 B 站账号？',
      message: '将删除本机保存的 access_token、refresh_token 与账号资料，不可撤销。'
          '这不会解除 B 站侧的授权，如需彻底解除请到 B 站账号设置里的授权管理操作。',
      confirmLabel: '退出登录',
    );
    if (!ok) return;
    await authSession.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return AnimatedBuilder(
      animation: authSession,
      builder: (_, __) => GlassPanel(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: SectionTitle(title: 'B 站账号')),
                if (authSession.busy)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (authSession.sandbox) _sandboxTag(),
            _body(context, sub),
            if (authSession.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _notice(authSession.error, AppStatus.danger),
            ],
            const SizedBox(height: 12),
            _boundary(sub),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Color sub) {
    final s = authSession;
    switch (s.status) {
      case AuthStatus.unknown:
        return _text('正在读取授权服务配置…', sub);
      case AuthStatus.unconfigured:
        return _unconfigured(sub);
      case AuthStatus.unavailable:
        return _unavailable(sub);
      case AuthStatus.signedOut:
        return _signedOut(sub);
      case AuthStatus.authorizing:
        return _authorizing(sub);
      case AuthStatus.signedIn:
        return _signedIn(sub);
      case AuthStatus.error:
        return _errorState(sub);
    }
  }

  Widget _unconfigured(Color sub) {
    final missing = authSession.config?.missing ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _notice('未配置官方开放平台凭证，登录入口已停用。', AppStatus.danger),
        const SizedBox(height: 10),
        _text(
          '官方 OAuth 2.0 要求先在 openhome.bilibili.com 完成开发者入驻、创建应用、'
          '申请并审核通过 scope、备案授权回调域。本应用不会用 Cookie 或抓登录态的方式冒充官方登录。',
          sub,
        ),
        if (missing.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _kv('待配置', missing.join(' / '), sub),
        ],
        const SizedBox(height: 10),
        _kv('授权服务', ApiConfig.oauthDisplayBase, sub),
        const SizedBox(height: 12),
        GlassChip(
          label: '重新检测配置',
          icon: Icons.refresh_rounded,
          tint: AppColors.pink,
          radius: 11,
          onTap: authSession.busy ? null : () => authSession.refreshConfig(),
        ),
      ],
    );
  }

  Widget _unavailable(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _notice('授权服务不可用。', AppStatus.danger),
        const SizedBox(height: 10),
        _text(
          '官方 OAuth 的 client_secret 只能保存在服务端，客户端无法独立完成授权码换 token。'
          '请启动 BFF 或用 --dart-define=BFF_URL=... 指向已部署的授权服务。',
          sub,
        ),
        const SizedBox(height: 10),
        _kv('授权服务', ApiConfig.oauthDisplayBase, sub),
        const SizedBox(height: 12),
        GlassChip(
          label: '重试',
          icon: Icons.refresh_rounded,
          tint: AppColors.pink,
          radius: 11,
          onTap: authSession.busy ? null : () => authSession.refreshConfig(),
        ),
      ],
    );
  }

  Widget _signedOut(Color sub) {
    final cfg = authSession.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _text(
          '通过 B 站官方 OAuth 2.0 授权页登录。全程在系统浏览器完成，'
          '本应用不接触账号密码；授权成功后凭证保存在本机，可在下方「数据边界」查看明细。',
          sub,
        ),
        const SizedBox(height: 10),
        _kv('接入方式', '官方授权码 + 服务端换取 token', sub),
        _kv('申请权限', (cfg?.scopes ?? const <String>[]).join(', '), sub),
        _kv('授权服务', ApiConfig.oauthDisplayBase, sub),
        if ((cfg?.redirectUri ?? '').isNotEmpty)
          _kv('回调地址', cfg!.redirectUri, sub),
        const SizedBox(height: 12),
        GlassChip(
          label: authSession.sandbox ? '开始演示授权' : '使用 B 站官方账号登录',
          icon: Icons.login_rounded,
          tint: AppColors.pink,
          radius: 11,
          onTap: authSession.busy ? null : _login,
        ),
      ],
    );
  }

  Widget _authorizing(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _notice(
          authSession.sandbox
              ? '已在当前页面打开演示授权页，点「同意授权」即可继续。'
              : '已打开 B 站官方授权页，请在浏览器中完成授权。',
          AppColors.pink,
        ),
        const SizedBox(height: 10),
        _text(
          'Web 端授权完成后会自动返回并登录；桌面 / 手机端请在回调页复制「一次性授权码」，'
          '粘贴到下面完成登录。该码 60 秒有效且只能使用一次，不含任何账号密码。',
          sub,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ticket,
          decoration: InputDecoration(
            labelText: '一次性授权码',
            hintText: '粘贴回调页显示的 ticket',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) authSession.completeWithTicket(v);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            GlassChip(
              label: '完成登录',
              icon: Icons.check_rounded,
              tint: AppColors.pink,
              radius: 11,
              onTap: authSession.busy
                  ? null
                  : () => authSession.completeWithTicket(_ticket.text),
            ),
            GlassChip(
              label: '取消',
              icon: Icons.close_rounded,
              radius: 11,
              onTap: () => authSession.cancelAuthorizing(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signedIn(Color sub) {
    final s = authSession;
    final t = s.tokens!;
    final u = s.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.pink.withOpacity(0.16),
              backgroundImage: (u?.face ?? '').isNotEmpty
                  ? NetworkImage(ApiConfig.image(u!.face))
                  : null,
              child: (u?.face ?? '').isEmpty
                  ? const Icon(Icons.person_rounded,
                      size: 21, color: AppColors.pink)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(u?.name ?? '已授权用户',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    t.isExpired ? '登录已过期，请重新授权' : '已通过官方 OAuth 2.0 授权',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: t.isExpired
                            ? AppStatus.danger
                            : AppStatus.success),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kv('openid', _mask(u?.openid ?? ''), sub),
        _kv('授权权限', t.scopes.isEmpty ? '—' : t.scopes.join(', '), sub),
        _kv('凭证有效期', t.expiresText, sub),
        _kv('本地保存', s.storageAvailable ? '是（仅本机）' : '否（当前平台不支持持久化）', sub),
        if (!s.storageAvailable) ...<Widget>[
          const SizedBox(height: 8),
          _text('当前平台缺少 shared_preferences 原生实现，登录态仅在本次会话有效。', sub),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            GlassChip(
              label: '刷新凭证',
              icon: Icons.autorenew_rounded,
              tint: AppColors.pink,
              radius: 11,
              onTap: s.busy ? null : () => authSession.refreshNow(),
            ),
            GlassChip(
              label: '读取资料',
              icon: Icons.person_search_rounded,
              radius: 11,
              onTap: s.busy ? null : () => authSession.reloadProfile(),
            ),
            GlassChip(
              label: '退出登录',
              icon: Icons.logout_rounded,
              radius: 11,
              onTap: _signOut,
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorState(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _notice('登录未完成。', AppStatus.danger),
        const SizedBox(height: 12),
        GlassChip(
          label: '返回',
          icon: Icons.arrow_back_rounded,
          tint: AppColors.pink,
          radius: 11,
          onTap: () => authSession.refreshConfig(),
        ),
      ],
    );
  }

  Widget _boundary(Color sub) {
    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.all(11),
      tint: AppColors.pink.withOpacity(0.08),
      showSheen: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('本地数据边界',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _text(
            '本机保存：access_token、refresh_token、过期时间、已授权 scope、openid / 昵称 / 头像。'
            '不保存：密码、Cookie、SESSDATA、bili_jct、client_secret、授权码 code。'
            'token 由用户在官方页面授权后取得，仅留在本机、不上传；'
            'shared_preferences 不是硬件加密存储，真机发布建议改用 Keychain / Keystore。',
            sub,
          ),
        ],
      ),
    );
  }

  Widget _sandboxTag() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '演示授权模式 · 非 B 站官方 · 仅用于链路自检',
        style: TextStyle(fontSize: 11, color: Color(0xFFB95C15),
            fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 11.5, color: color, height: 1.5)),
        ),
      ],
    );
  }

  Widget _text(String text, Color sub) =>
      Text(text, style: TextStyle(fontSize: 12, height: 1.65, color: sub));

  Widget _kv(String label, String value, Color sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(fontSize: 11.5, color: sub)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  String _mask(String raw) {
    if (raw.isEmpty) return '—';
    if (raw.length <= 8) return raw;
    return '${raw.substring(0, 4)}…${raw.substring(raw.length - 4)}';
  }
}
