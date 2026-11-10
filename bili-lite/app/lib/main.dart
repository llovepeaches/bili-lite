import 'package:flutter/material.dart';

import 'app.dart';
import 'state/globals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 本地数据先就绪；服务探测在 AppState.init 里异步进行，不阻塞首屏
  await library.load();
  await appState.init();

  // 官方 OAuth 2.0：授权完成后 B 站（或本地演示授权页）会重定向回
  // /?oauth_ticket=<一次性码>。App 启动时领取凭证并写入本地。
  await authSession.init();
  try {
    final ticket = Uri.base.queryParameters['oauth_ticket'];
    if (ticket != null && ticket.isNotEmpty) {
      await authSession.completeWithTicket(ticket);
    }
  } catch (_) {
    // 非 Web 端或异常 embedder 下 Uri.base 可能不可用，忽略即可
  }

  runApp(const BiliLiteApp());
}
