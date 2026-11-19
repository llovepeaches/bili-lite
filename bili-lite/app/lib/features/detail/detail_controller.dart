import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/globals.dart';
import '../player/player_controller.dart';

/// 视频详情控制器：详情数据 + 评论列表 + 分页 + 排序。
///
/// 重构前这些状态与 UI 全塞在 `detail_page.dart`（756 行）里，页面同时负责
/// 发请求、维护评论游标、画播放器、画评论卡片、画简介卡片。拆分之后逻辑可单测，
/// 视图只负责画。组织方式对齐 PiliPlus 的
/// `pages/<feature>/{controller,view}.dart`。
class DetailController extends ChangeNotifier {
  DetailController({required this.video, BiliRepository? repository})
      : _repo = repository ?? repo;

  /// 从列表页带过来的视频。详情接口返回前先用它占位，避免界面空白。
  final Video video;

  final BiliRepository _repo;

  VideoDetail? _detail;
  final List<Comment> _comments = <Comment>[];
  int _commentCount = 0;
  int _pn = 1;
  int _sort = 2;

  bool _loadingComments = false;
  bool _loadingMore = false;

  String? _detailError;
  String? _commentError;
  String _source = '';
  bool _disposed = false;

  /// 内嵌播放器：点封面后才创建，避免进详情页就加载视频流。
  ///
  /// 生命周期随之绑定：[startPlayback] 创建并起播，[dispose] 统一释放。
  /// 旧版是 push 一个独立 [PlayerPage]，这里改成详情页内嵌，
  /// 用户不必「二次打开页面」才能播放。
  PlayerController? _player;
  PlayerController? get player => _player;

  /// 详情接口返回后的完整视频（含简介、标签、分 P）。
  Video get resolvedVideo => _detail?.video ?? video;

  String get source => _source;

  List<Comment> get comments => _comments;

  int get commentCount => _commentCount;

  int get sort => _sort;

  bool get loadingComments => _loadingComments;

  bool get loadingMore => _loadingMore;

  String? get detailError => _detailError;

  String? get commentError => _commentError;

  List<PageInfo> get pages => _detail?.pages ?? const <PageInfo>[];

  List<String> get tags => _detail?.tags ?? const <String>[];

  String get desc => resolvedVideo.desc;

  /// 详情与评论一起加载。
  Future<void> load() async {
    await Future.wait<void>(<Future<void>>[
      loadDetail(),
      loadComments(refresh: true),
    ]);
  }

  Future<void> loadDetail() async {
    try {
      final res = await _repo.video(video.bvid, aid: video.aid);
      _detail = res.data;
      _source = res.source;
      _detailError = null;
    } catch (e) {
      _detailError = e.toString();
    }
    _notify();
  }

  /// 加载评论。
  ///
  /// [refresh] 重新从第一页开始，[more] 追加下一页。
  Future<void> loadComments({bool refresh = false, bool more = false}) async {
    final aid = resolvedVideo.aid.isNotEmpty ? resolvedVideo.aid : video.aid;
    if (_loadingComments || aid.isEmpty) return;
    if (more) {
      _loadingMore = true;
      _pn += 1;
    } else if (refresh) {
      _pn = 1;
      _comments.clear();
    }
    _loadingComments = true;
    _notify();
    try {
      final res = await _repo.reply(aid, pn: _pn, ps: 20, sort: _sort);
      _comments.addAll(res.data.list);
      _commentCount = res.data.count;
      _commentError = null;
    } catch (e) {
      // 加载更多失败时页码要回退，否则用户点「重试」会跳过一页评论。
      if (more) _pn -= 1;
      _commentError = e.toString();
    } finally {
      _loadingMore = false;
      _loadingComments = false;
      _notify();
    }
  }

  /// 切换评论排序（0 = 最新，2 = 热门）。
  Future<void> changeSort(int sort) async {
    if (_sort == sort) return;
    _sort = sort;
    await loadComments(refresh: true);
  }

  /// 在详情页内启动播放（幂等：重复点击不会重复创建播放器）。
  ///
  /// cid 在列表卡片里可能为空，[PlayerController.load] 内部会补一次详情，
  /// 因此这里直接用当前 [resolvedVideo] 的 bvid / cid 即可。
  void startPlayback() {
    if (_player != null) return;
    final current = resolvedVideo;
    final controller = PlayerController(
      bvid: current.bvid.isNotEmpty ? current.bvid : video.bvid,
      cid: current.cid,
      // 复用详情仓库，便于测试注入假数据，也让请求走同一条来源兜底链路。
      repository: _repo,
    );
    _player = controller;
    // 位置推进定时器与加载一起启动，无论从封面还是 AppBar 起播，
    // 弹幕时间轴都能被驱动（不必依赖某个特定视图入口）。
    controller.attachTicker();
    controller.load();
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _player?.dispose();
    super.dispose();
  }
}
