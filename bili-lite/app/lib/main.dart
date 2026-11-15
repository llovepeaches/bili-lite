import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/server_config.dart';
import 'core/storage.dart';
import 'state/globals.dart';
import 'state/update_service.dart';

/// 启动优化（v0.1.0）
/// ---------------------------------------------------------------------------
/// 旧实现把 6 个本地初始化串行 await，并且把官方 OAuth 备用通道的 BFF 探活
/// （`AuthSession.refreshConfig()`，内部 15s 超时）也放在 `runApp()` 之前。
/// 独立安装包里那个授权服务必然连不上，于是一打开就要白屏等满超时。
///
/// 现在：
///   ① LocalStore 单独先初始化（它的 init 有幂等短路，并发调用会读到未就绪的
///      _prefs 而退化成内存态，必须单独 await）；
///   ② 其余本地初始化并行执行；
///   ③ 立刻 runApp 出首屏；
///   ④ 网络探测（BFF 健康、OAuth 探活、更新检查）全部挪到首屏之后，
///      各自带 8s 上限与异常兜底，失败不影响看内容。
Future<void> main() async {
  final sw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  await LocalStore.instance.init();

  await Future.wait<void>(<Future<void>>[
    library.load(),
    searchHistory.load(),
    ServerConfig.instance.init(),
    appState.init(),
    qrSession.init(),
    authSession.initLocal(),
  ]);

  runApp(const BiliLiteApp());
  if (kDebugMode) {
    debugPrint('[startup] 首屏就绪 ${sw.elapsedMilliseconds}ms（网络探测已移到后台）');
  }

  unawaited(_backgroundInit());
}

/// 首屏之后才做的网络工作：BFF 健康探测、官方 OAuth 备用通道探活、更新检查、
/// 以及 Web 端 OAuth 回调领取。这些全是「锦上添花」的状态，失败不影响主流程。
Future<void> _backgroundInit() async {
  await Future.wait<void>(<Future<void>>[
    _guarded(appState.refreshServerInfo),
    _guarded(authSession.refreshConfig),
    _guarded(() async {
      await UpdateService.instance.autoCheck();
    }),
  ]);

  // Web 端官方 OAuth 授权完成后会重定向回 /?oauth_ticket=<一次性码>。
  // 只在确实带 ticket 时领取，且不再挡住首屏。
  try {
    final ticket = Uri.base.queryParameters['oauth_ticket'];
    if (ticket != null && ticket.isNotEmpty) {
      await _guarded(() => authSession.completeWithTicket(ticket));
    }
  } catch (_) {
    // 非 Web 端或异常 embedder 下 Uri.base 可能不可用，忽略即可
  }
}

/// 后台探测统一兜底：超时与异常都静默失败，设置页保留手动入口。
Future<void> _guarded(Future<void> Function() work) async {
  try {
    await work().timeout(const Duration(seconds: 8));
  } catch (_) {
    // 有意忽略：离线 / BFF 未部署是独立安装包的常态
  }
}
