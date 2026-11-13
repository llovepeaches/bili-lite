/// 条件导出：Web 编译走 iframe 实现，其余平台走 stub。
///
/// `kCanEmbedOfficialPlayer` 随平台一起切换：web 端为 true（可用
/// HtmlElementView 承载官方 iframe），原生端为 false（降级为系统浏览器）。
/// 业务代码只读这一个常量，能力判断与实际实现不会再出现两个真相来源。
export 'player_view_stub.dart'
    if (dart.library.html) 'player_view_web.dart';
