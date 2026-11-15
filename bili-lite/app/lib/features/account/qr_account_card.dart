import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import 'account_identity.dart';
import 'qr_login_sheet.dart';

/// 「B 站账号」主卡片：扫码登录。
///
/// 它取代了原来把官方 OAuth 作为唯一入口的账号面板。原因：
/// 官方 OAuth 必须有一个持有 client_secret 的授权服务端，而独立安装包里
/// 没有这个服务（真机上 `10.0.2.2` 又是模拟器专用别名），结果就是所有装了
/// APK 的用户都只能看到「授权服务不可用」。扫码登录由客户端直连 B 站完成，
/// 不需要任何服务端，因此作为默认主通道；官方 OAuth 保留在下方高级区域。
class QrAccountCard extends StatelessWidget {
  const QrAccountCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AccountIdentity.changes,
      builder: (_, __) => GlassPanel(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: SectionTitle(title: 'B 站账号')),
                if (qrSession.busy)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (AccountIdentity.signedIn)
              _signedIn(context)
            else
              _signedOut(context),
          ],
        ),
      ),
    );
  }

  Widget _signedOut(BuildContext context) {
    final sub = context.subTextColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _text(
          '用 B 站 App 扫码即可登录，不需要开放平台凭证，也不需要单独部署授权服务。'
          '下方还提供账号密码、短信验证码与 Cookie 登录；四条通道拿到的是'
          '同一份 Web 登录 Cookie，只保存在本机。',
          sub,
        ),
        const SizedBox(height: 12),
        _kv('登录方式', '扫码 / 密码 / 短信 / Cookie', sub),
        _kv('授权服务', '不需要', sub),
        const SizedBox(height: 14),
        GlassChip(
          label: '扫码登录',
          icon: Icons.qr_code_scanner_rounded,
          tint: AppColors.pink,
          radius: 11,
          onTap: () => showQrLoginSheet(context),
        ),
        const SizedBox(height: 12),
        _boundary(sub),
      ],
    );
  }

  Widget _signedIn(BuildContext context) {
    final sub = context.subTextColor;
    final viaQr = AccountIdentity.viaQr;
    final face = AccountIdentity.face;
    final name = AccountIdentity.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.pink.withOpacity(0.16),
              backgroundImage:
                  face.isNotEmpty ? NetworkImage(ApiConfig.image(face)) : null,
              child: face.isEmpty
                  ? const Icon(Icons.person_rounded,
                      size: 21, color: AppColors.pink)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(AccountIdentity.subtitle,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppStatus.success)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kv('登录方式', AccountIdentity.methodLabel, sub),
        if (viaQr && (qrSession.user?.mid ?? '').isNotEmpty)
          _kv('UID', qrSession.user!.mid, sub),
        _kv('本地保存', '是（仅本机）', sub),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (viaQr)
              GlassChip(
                label: '刷新资料',
                icon: Icons.autorenew_rounded,
                radius: 11,
                onTap: () => qrSession.reloadProfile(),
              ),
            GlassChip(
              label: '退出登录',
              icon: Icons.logout_rounded,
              radius: 11,
              onTap: () => _signOut(context),
            ),
          ],
        ),
        if (viaQr && qrSession.message.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(qrSession.message,
              style: TextStyle(fontSize: 11.5, color: sub)),
        ],
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
    // 两路都可能登录过，退出时一起清，避免留下半套凭证。
    final ok = await showConfirmDialog(
      context,
      title: '退出 B 站账号？',
      message: '将删除本机保存的登录凭证（Web 登录为 B 站登录 Cookie，'
          '官方 OAuth 为 access_token / refresh_token）与账号资料，不可撤销。',
      confirmLabel: '退出登录',
    );
    if (!ok) return;
    await qrSession.signOut();
    await authSession.signOut();
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
            '扫码 / 密码 / 短信 / Cookie 四条通道都会保存同一份 B 站 Web 登录 Cookie'
            '（SESSDATA / bili_jct / DedeUserID 等）以及昵称 / 头像 / mid；'
            '不保存密码、验证码。Cookie 只发往 bilibili.com，'
            '不上传第三方。本地存储不是硬件加密存储，真机发布建议改用 '
            'Keychain / Keystore。若改用下方官方 OAuth 通道，则保存的是 '
            'access_token / refresh_token，不碰 Cookie。',
            sub,
          ),
        ],
      ),
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
              child: Text(label, style: TextStyle(fontSize: 11.5, color: sub))),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}
