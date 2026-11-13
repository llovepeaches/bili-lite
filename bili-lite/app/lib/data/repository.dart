import '../core/config.dart';
import 'api_client.dart';
import 'models.dart';

/// 业务仓库：页面只调用这里，不直接接触 URL 和解析细节。
///
/// 接口路径统一取自 `ApiConfig.endpoints`，不再散落硬编码字符串。
class BiliRepository {
  BiliRepository({ApiClient? client}) : _api = client ?? ApiClient.instance;

  final ApiClient _api;

  Future<ApiResponse<HealthInfo>> health() => _api.get(
        ApiConfig.endpoint('health'),
        parse: (raw) => HealthInfo.fromJson(raw),
      );

  Future<ApiResponse<MetaInfo>> meta() => _api.get(
        ApiConfig.endpoint('meta'),
        parse: (raw) => MetaInfo.fromJson(raw),
      );

  /// 首页推荐流。
  ///
  /// [freshIdx] 是 B 站的「换一批」游标；[skipCache] 让服务端绕过本地缓存
  /// 重新取数，两者配合才能让下拉刷新真正拿到新内容。
  Future<ApiResponse<List<Video>>> feed({
    int ps = 20,
    int freshIdx = 1,
    bool skipCache = false,
  }) =>
      _api.get(
        ApiConfig.endpoint('feed'),
        query: {
          'ps': '$ps',
          'fresh_idx': '$freshIdx',
          if (skipCache) 'skip_cache': '1',
        },
        parse: (raw) => (raw as List<dynamic>? ?? <dynamic>[])
            .map((e) => Video.fromJson(e))
            .toList(),
      );

  Future<ApiResponse<RankResult>> rank({int rid = 0, bool skipCache = false}) =>
      _api.get(
        ApiConfig.endpoint('rank'),
        query: {'rid': '$rid', if (skipCache) 'skip_cache': '1'},
        parse: (raw) => RankResult.fromJson(raw),
      );

  Future<ApiResponse<List<Video>>> popular({
    int pn = 1,
    int ps = 20,
    bool skipCache = false,
  }) =>
      _api.get(
        ApiConfig.endpoint('popular'),
        query: {
          'pn': '$pn',
          'ps': '$ps',
          if (skipCache) 'skip_cache': '1',
        },
        parse: (raw) => (raw as List<dynamic>? ?? <dynamic>[])
            .map((e) => Video.fromJson(e))
            .toList(),
      );

  Future<ApiResponse<SearchResult>> search(String keyword, {int page = 1}) =>
      _api.get(
        ApiConfig.endpoint('search'),
        query: {'keyword': keyword, 'page': '$page'},
        parse: (raw) => SearchResult.fromJson(raw),
      );

  Future<ApiResponse<VideoDetail>> video(String bvid, {String aid = ''}) =>
      _api.get(
        ApiConfig.endpoint('video'),
        query: bvid.isNotEmpty ? {'bvid': bvid} : {'aid': aid},
        parse: (raw) => VideoDetail.fromJson(raw),
      );

  Future<ApiResponse<CommentPage>> reply(
    String aid, {
    int pn = 1,
    int ps = 20,
    int sort = 2,
  }) =>
      _api.get(
        ApiConfig.endpoint('reply'),
        query: {'aid': aid, 'pn': '$pn', 'ps': '$ps', 'sort': '$sort'},
        parse: (raw) => CommentPage.fromJson(raw),
      );

  /// 播放地址（应用内播放）。
  ///
  /// [qn] 是清晰度码：16=360P、32=480P、64=720P、80=1080P、112=1080P高码率、
  /// 116=1080P 60帧、120=4K。上游只认它自己那一套码值，别处不要混用。
  Future<ApiResponse<PlayUrl>> playUrl(
    String bvid,
    String cid, {
    int qn = 64,
  }) =>
      _api.get(
        ApiConfig.endpoint('playurl'),
        query: {'bvid': bvid, 'cid': cid, 'qn': '$qn'},
        parse: (raw) => PlayUrl.fromJson(raw),
        timeout: const Duration(seconds: 20),
      );

  /// 弹幕列表（播放器叠加层用）。
  ///
  /// 服务端已经把上游的 deflate XML 解压并解析成 JSON；
  /// 直连模式下由 `BiliDirect` 完成同样的工作，结构保持一致。
  Future<ApiResponse<DanmakuList>> danmaku(String cid) => _api.get(
        ApiConfig.endpoint('danmaku'),
        query: {'oid': cid},
        parse: (raw) => DanmakuList.fromJson(raw),
        timeout: const Duration(seconds: 20),
      );
}
