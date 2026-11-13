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

  Future<ApiResponse<List<Video>>> feed({int ps = 20, int freshIdx = 1}) =>
      _api.get(
        ApiConfig.endpoint('feed'),
        query: {'ps': '$ps', 'fresh_idx': '$freshIdx'},
        parse: (raw) => (raw as List<dynamic>? ?? <dynamic>[])
            .map((e) => Video.fromJson(e))
            .toList(),
      );

  Future<ApiResponse<RankResult>> rank({int rid = 0}) => _api.get(
        ApiConfig.endpoint('rank'),
        query: {'rid': '$rid'},
        parse: (raw) => RankResult.fromJson(raw),
      );

  Future<ApiResponse<List<Video>>> popular({int pn = 1, int ps = 20}) =>
      _api.get(
        ApiConfig.endpoint('popular'),
        query: {'pn': '$pn', 'ps': '$ps'},
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
}
