import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/globals.dart';

/// 首页的三个频道。
enum HomeChannel {
  recommended('推荐'),
  popular('热门'),
  rank('排行榜');

  const HomeChannel(this.label);

  final String label;
}

/// 首页控制器：管数据、分页游标与加载状态，视图只负责画。
///
/// 重构前这些状态全部塞在 `HomePage` 的 State 里（280 行），页面同时承担
/// 「发请求 / 合并去重 / 记页码 / 决定显示什么」四件事，没法单独测。
/// 拆出来之后逻辑与渲染分离，也和 PiliPlus 的
/// `pages/<feature>/{controller,view}.dart` 组织方式一致。
class HomeController extends ChangeNotifier {
  HomeController({BiliRepository? repository})
      : _repo = repository ?? repo {
    _videos[HomeChannel.recommended] = <Video>[];
    _videos[HomeChannel.popular] = <Video>[];
    _videos[HomeChannel.rank] = <Video>[];
  }

  final BiliRepository _repo;

  final Map<HomeChannel, List<Video>> _videos =
      <HomeChannel, List<Video>>{};
  final Map<HomeChannel, String> _sources = <HomeChannel, String>{};
  final Map<HomeChannel, String?> _errors = <HomeChannel, String?>{};
  final Map<HomeChannel, bool> _loading = <HomeChannel, bool>{};

  HomeChannel _channel = HomeChannel.recommended;
  int _freshIdx = 1;
  int _popularPage = 1;
  int _rid = 0;
  String _rankNote = '';
  bool _loadingMore = false;
  bool _disposed = false;

  HomeChannel get channel => _channel;

  /// 当前频道的视频列表。
  List<Video> videosOf(HomeChannel channel) =>
      _videos[channel] ?? const <Video>[];

  /// 当前频道的数据来源标记（live / cache / mock）。
  String sourceOf(HomeChannel channel) => _sources[channel] ?? '';

  /// 当前频道的错误信息。
  String? errorOf(HomeChannel channel) => _errors[channel];

  bool loadingOf(HomeChannel channel) => _loading[channel] ?? false;

  bool get loadingMore => _loadingMore;

  /// 排行榜当前分区 rid（0 表示全站）。
  int get rid => _rid;

  String get rankNote => _rankNote;

  /// 切换频道。首次进入某个频道时自动拉数据。
  void selectChannel(HomeChannel channel) {
    if (_channel == channel) return;
    _channel = channel;
    _notify();
    load(channel);
  }

  /// 当前频道是否还有下一页。
  bool hasMore(HomeChannel channel) {
    if (channel == HomeChannel.recommended) return true;
    if (channel == HomeChannel.popular) return _popularPage < 10;
    return false;
  }

  /// 加载指定频道。
  ///
  /// [more] 是加载更多（追加），[force] 是强制刷新（换一批）。
  Future<void> load(
    HomeChannel channel, {
    bool more = false,
    bool force = false,
  }) async {
    if (_loading[channel] == true) return;
    if (!more && !force && videosOf(channel).isNotEmpty) return;

    if (more) _loadingMore = true;
    _loading[channel] = true;
    _notify();

    try {
      if (channel == HomeChannel.recommended) {
        // 关键：force（换一批）必须**递增** freshIdx，而不是重置为 1。
        // B 站的 fresh_idx 就是「换一批」的游标，重置回 1 会拿到和上次
        // 完全相同的一批稿件 —— 这正是之前「下拉刷新没反应」的原因。
        // 配合服务端的 skip_cache=1 一起绕过 60 秒的本地缓存。
        if (more || force) {
          _freshIdx += 1;
        }
        final res = await _repo.feed(
          ps: 20,
          freshIdx: _freshIdx,
          skipCache: force,
        );
        _videos[HomeChannel.recommended] = more
            ? _merge(videosOf(HomeChannel.recommended), res.data)
            : res.data;
        _sources[HomeChannel.recommended] = res.source;
        _errors[HomeChannel.recommended] = null;
      } else if (channel == HomeChannel.popular) {
        if (more) {
          _popularPage += 1;
        } else if (force) {
          _popularPage = 1;
        }
        final res = await _repo.popular(
          pn: _popularPage,
          ps: 20,
          skipCache: force,
        );
        _videos[HomeChannel.popular] = more
            ? _merge(videosOf(HomeChannel.popular), res.data)
            : res.data;
        _sources[HomeChannel.popular] = res.source;
        _errors[HomeChannel.popular] = null;
      } else {
        final res = await _repo.rank(rid: _rid, skipCache: force);
        _videos[HomeChannel.rank] = res.data.list;
        _rankNote = res.data.note;
        _sources[HomeChannel.rank] = res.source;
        _errors[HomeChannel.rank] = null;
      }
    } catch (e) {
      _errors[channel] = e.toString();
    } finally {
      _loadingMore = false;
      _loading[channel] = false;
      _notify();
    }
  }

  /// 切换排行榜分区。
  Future<void> changePartition(int rid) async {
    if (_rid == rid) return;
    _rid = rid;
    await load(HomeChannel.rank, force: true);
  }

  /// 按 bvid 去重合并。推荐流「换一批」会返回重复稿件，直接 append 会
  /// 出现同一个视频连续出现两次。
  static List<Video> _merge(List<Video> base, List<Video> incoming) {
    final seen = base.map((e) => e.bvid).toSet();
    final result = List<Video>.from(base);
    for (final v in incoming) {
      if (v.bvid.isNotEmpty && seen.add(v.bvid)) result.add(v);
    }
    return result;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
