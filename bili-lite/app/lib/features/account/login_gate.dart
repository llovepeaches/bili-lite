import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../widgets/glass.dart';
import 'account_entry.dart';
import 'account_identity.dart';

/// 「有些内容要登录才能使用」的统一落点。
///
/// 上一轮补齐了扫码 / 密码 / 短信 / Cookie 四条登录通道，但登录态此前只用于
/// 展示身份：评论只放热评、弹幕与播放地址被上游按访客身份限流时，界面既不
/// 解释原因、也不给入口。这里把门槛收成一个组件 + 一个函数：
/// 未登录时明确告诉用户「这一块为什么不全」并提供登录入口；
/// 已登录时直接放行，原生直连请求也会带上登录 Cookie（见 BiliDirect.userCookie）。
class LoginRequiredHint extends StatelessWidget {
  const LoginRequiredHint({Key? key, this.feature = '完整内容'}) : super(key: key);

  /// 需要登录的能力名，用于拼一行短提示，不写长说明。
  final String feature;

  @override
  Widget build(BuildContext context) {
    if (AccountIdentity.signedIn) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: () => requireLogin(context),
        child: Row(
          children: <Widget>[
            Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.pink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$feature需要登录 B 站账号',
                style: TextStyle(fontSize: 11.5, color: context.subTextColor),
              ),
            ),
            Text(
              '去登录',
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// 需要登录的操作统一走这里。
///
/// 返回「调用时是否已经登录」；账号面板关闭后再判断一次，用户在面板里
/// 刚完成登录也能直接继续，不必再点一遍。
Future<bool> requireLogin(BuildContext context) async {
  if (AccountIdentity.signedIn) return true;
  await showAccountSheet(context);
  return AccountIdentity.signedIn;
}
