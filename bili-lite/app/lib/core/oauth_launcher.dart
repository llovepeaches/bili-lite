/// 条件导出：Web 走同页导航，原生走系统浏览器。
export 'oauth_launcher_stub.dart'
    if (dart.library.html) 'oauth_launcher_web.dart';
