import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage.dart';

/// 搜索历史。
///
/// 重构前这段逻辑直接写在 `features/search/search_page.dart` 里，
/// 自己持有一个 TextEditingController 之外的状态并直接调 SharedPreferences——
/// 于是「本地数据」被拆成两套互不相干的存储路径，主题/收藏走 state 层、
/// 搜索历史走页面层，清空时也漏掉了它。
///
/// 现在归入 state 层，与收藏 / 历史 / 稍后再看保持同一套存储约定。
class SearchHistory extends ChangeNotifier {
  static const String _key = 'bili_lite_search_history';
  static const int _max = 10;

  List<String> _items = <String>[];

  /// 只读副本，避免外部直接改内部列表。
  List<String> get items => List<String>.unmodifiable(_items);

  bool _loaded = false;
  bool get loaded => _loaded;

  /// 本地持久化是否真的落到磁盘。
  bool get storagePersistent => LocalStore.instance.persistent;

  Future<void> load() async {
    await LocalStore.instance.init();
    _items = LocalStore.instance.getStringListFromJson(_key);
    _loaded = true;
    notifyListeners();
  }

  /// 记录一次搜索：去重后置顶，最多保留 10 条。
  Future<void> add(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;
    _items = <String>[
      trimmed,
      ..._items.where((e) => e != trimmed),
    ];
    if (_items.length > _max) {
      _items = _items.sublist(0, _max);
    }
    notifyListeners();
    await LocalStore.instance.setString(_key, json.encode(_items));
  }

  Future<void> clear() async {
    _items = <String>[];
    notifyListeners();
    await LocalStore.instance.remove(_key);
  }
}
