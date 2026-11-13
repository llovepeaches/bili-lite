/// B 站官方「站外（外链）播放器」。
///
/// 官方文档：https://player.bilibili.com
/// 这是官方为第三方页面提供的公开嵌入方式。播放器、鉴权、清晰度与版权控制
/// 全部由官方域名负责；本应用只传 bvid / 分 P，**不解析播放地址、不接触
/// 视频流、不向播放器注入任何登录态**（本机 OAuth 凭证只用于开放平台只读接口）。
/// 这样既不违反用户协议里「不得以自动程序获取
/// 平台服务、内容、数据」的约束，也让用户不离开应用就能观看。
class BiliPlayer {
  BiliPlayer._();

  static const String host = 'player.bilibili.com';
  static const String docsUrl = 'https://player.bilibili.com';

  /// 官方嵌入地址。参数以 player.bilibili.com 公布的表为准。
  static String embedUrl({
    required String bvid,
    String aid = '',
    int page = 1,
    bool highQuality = true,
    bool danmaku = false,
  }) {
    final params = <String, String>{
      if (bvid.isNotEmpty) 'bvid': bvid else 'aid': aid,
      'p': page < 1 ? '1' : '$page',
      'as_wide': '1',
      'high_quality': highQuality ? '1' : '0',
      'danmaku': danmaku ? '1' : '0',
      // 浏览器会拦截无用户交互的有声自动播放，交给用户手动点播放。
      'autoplay': '0',
    };
    return Uri.https(host, '/player.html', params).toString();
  }

  /// 平台能力判断已移至 `features/player/player_view.dart` 的
  /// `kCanEmbedOfficialPlayer`：能力标记与承载实现放在同一个平台文件，
  /// 避免「这里说能内嵌、那边却返回 null」的双真相。
  /// 官方视频页：评论 / 投币 / 点赞等需要账号的互动在此完成。
  static String officialPage(String bvid) =>
      'https://www.bilibili.com/video/$bvid';
}
