/// 条件导出：Web 编译走 iframe 实现，其余平台走 stub。
export 'player_view_stub.dart'
    if (dart.library.html) 'player_view_web.dart';
