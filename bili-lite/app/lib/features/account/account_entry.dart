import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../widgets/glass.dart';
import 'account_identity.dart';
import 'account_view.dart';
import 'passport_login_card.dart';
import 'qr_account_card.dart';
import 'server_config_card.dart';

/// 账号入口卡片：登录态的紧凑展示 + 一键展开完整登录面板。
///
/// 状态来自 [AccountIdentity]（合并扫码登录与官方 OAuth 两路），
/// 这样即使授权服务探活失败，已扫码登录的用户看到的仍是「已登录」。
class AccountEntry extends StatelessWidget {
  const AccountEntry({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return AnimatedBuilder(
      animation: AccountIdentity.changes,
      builder: (context, _) {
        return GlassPanel(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          onTap: () => _expand(context),
          child: Row(
            children: <Widget>[
              _avatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _title(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(),
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

  Widget _avatar() {
    final face = AccountIdentity.face;
    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.pink.withOpacity(0.16),
      backgroundImage:
          face.isNotEmpty ? NetworkImage(ApiConfig.image(face)) : null,
      child: face.isEmpty
          ? Icon(
              AccountIdentity.signedIn
                  ? Icons.person_rounded
                  : Icons.login_rounded,
              size: 21,
              color: AppColors.pink,
            )
          : null,
    );
  }

  String _title() {
    if (AccountIdentity.signedIn) return AccountIdentity.name;
    return '登录 B 站账号';
  }

  String _subtitle() => AccountIdentity.subtitle;

  Future<void> _expand(BuildContext context) async {
    await showAccountSheet(context);
  }
}

/// 展开完整的账号面板（底部弹层）。
///
/// 首页顶栏与「我的」页顶部共用这一个入口，保证行为一致。
/// 内容顺序刻意把「扫码登录」放最上面：它不需要任何服务端、也不需要
/// 人机验证，是成功率最高的通道。其次是「其他登录方式」（密码 / 短信 /
/// Cookie），官方 OAuth 及其授权服务设置收在最下方的可折叠「高级」区。
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  bool _advanced = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
            const QrAccountCard(),
            const SizedBox(height: 12),
            const PassportLoginCard(),
            const SizedBox(height: 12),
            GlassPanel(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              onTap: () => setState(() => _advanced = !_advanced),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.tune_rounded,
                      size: 17, color: AppColors.pink),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('官方 OAuth 与授权服务（高级 / 可选）',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  Icon(_advanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
                ],
              ),
            ),
            if (_advanced) ...<Widget>[
              const SizedBox(height: 12),
              const ServerConfigCard(),
              const SizedBox(height: 12),
              const AccountCard(),
            ],
          ],
        ),
      ),
    );
  }
}
