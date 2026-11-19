import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/globals.dart';
import 'space_filter.dart';

/// UP 主空间控制器。
///
/// 原先 `_SpaceViewState` 直接持有 `_loading / _error / _videos`。这里按项目
/// 其它页面已有的 controller/view 分层把它抽出来：请求、过滤与状态回调在
/// controller，视图只订阅变化并渲染，数据与路由行为均不变。
class SpaceController extends ChangeNotifier {
  SpaceController({required Owner owner, BiliRepository? repository})
      : _owner = owner,
        _repo = repository ?? repo;

  final Owner _owner;
  final BiliRepository _repo;

  bool _loading = true;
  String? _error;
  List<Video> _videos = <Video>[];
  bool _disposed = false;

  bool get loading => _loading;
  String? get error => _error;
  List<Video> get videos => _videos;

  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();

    try {
      final name = _owner.name.trim();
      if (name.isEmpty) throw StateError('缺少 UP 主名称');
      final res = await _repo.search(name);
      // 搜索结果可能混入同名 / 转载稿件，只保留 mid 一致的。
      _videos = filterOwnerVideos(res.data.list, _owner.mid);
      _loading = false;
    } catch (e) {
      _error = e.toString();
      _loading = false;
    }
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
