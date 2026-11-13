import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/globals.dart';

/// 搜索控制器：关键词、结果列表、分页与错误状态。
///
/// 搜索历史本身在 `SearchHistory`（state 层）里，这里只管本次搜索。
/// 拆出来之后「分页回退」「去重」这些规则可以单独测，不必拉起整个页面。
class SearchController extends ChangeNotifier {
  SearchController({BiliRepository? repository}) : _repo = repository ?? repo;

  final BiliRepository _repo;

  String _keyword = '';
  List<Video> _results = <Video>[];
  int _page = 1;
  int _pages = 0;
  int _total = 0;
  String _source = '';
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;
  bool _disposed = false;

  /// 当前关键词。空字符串表示停留在「未搜索」的引导页。
  String get keyword => _keyword;

  List<Video> get results => _results;

  int get total => _total;

  String get source => _source;

  String? get error => _error;

  bool get loading => _loading;

  bool get loadingMore => _loadingMore;

  bool get hasMore => _page < _pages;

  /// 执行搜索。
  ///
  /// [more] 为真时追加下一页；为假时从第一页重新开始。
  Future<void> search(String word, {bool more = false}) async {
    final keyword = word.trim();
    if (keyword.isEmpty || _loading) return;

    if (more) {
      if (_loadingMore || _page >= _pages) return;
      _loadingMore = true;
      _page += 1;
    } else {
      _page = 1;
      _results = <Video>[];
      _error = null;
      _keyword = keyword;
      await searchHistory.add(keyword);
    }

    _loading = true;
    _notify();

    try {
      final res = await _repo.search(keyword, page: _page);
      final seen = _results.map((e) => e.bvid).toSet();
      final added = <Video>[];
      for (final v in res.data.list) {
        if (seen.add(v.bvid)) added.add(v);
      }
      _results = more ? <Video>[..._results, ...added] : added;
      _pages = res.data.pages;
      _total = res.data.total;
      _source = res.source;
      _error = null;
    } catch (e) {
      // 加载更多失败时页码要回退，否则用户重试会跳过一页数据。
      if (more) _page -= 1;
      _error = e.toString();
    } finally {
      _loadingMore = false;
      _loading = false;
      _notify();
    }
  }

  /// 清空搜索状态，回到引导页。
  void clear() {
    _keyword = '';
    _results = <Video>[];
    _error = null;
    _source = '';
    _page = 1;
    _pages = 0;
    _total = 0;
    _notify();
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
