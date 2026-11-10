import 'package:flutter/material.dart';

import 'app.dart';
import 'state/globals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 本地数据先就绪；服务探测在 AppState.init 里异步进行，不阻塞首屏
  await library.load();
  await appState.init();
  runApp(const BiliLiteApp());
}
