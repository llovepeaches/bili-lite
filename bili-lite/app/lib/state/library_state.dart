import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage.dart';
import '../data/models.dart';

enum LibraryKind { favorites, history, watchLater }

class LibraryItem {
  final Video video;
  final int addedAt;

  const LibraryItem({required this.video, required this.addedAt});

  factory LibraryItem.fromJson(dynamic raw) {
    final j = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return LibraryItem(
      video: Video.fromJson(j['video']),
      addedAt: j['addedAt'] is int ? j['addedAt'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'video': video.toJson(),
        'addedAt': addedAt,
      };
}

/// 收藏 / 历史 / 稍后再看，全部存本地，不需要登录、不上传任何数据。
class LibraryState extends ChangeNotifier {
  static const String _keyFavorites = 'bili_lite_favorites';
  static const String _keyHistory = 'bili_lite_history';
  static const String _keyWatchLater = 'bili_lite_watch_later';

  static const int _maxHistory = 200;
  static const int _maxLists = 500;

  final Map<LibraryKind, List<LibraryItem>> _data = {
    LibraryKind.favorites: <LibraryItem>[],
    LibraryKind.history: <LibraryItem>[],
    LibraryKind.watchLater: <LibraryItem>[],
  };

  bool _loaded = false;
  bool get loaded => _loaded;

  /// 本地持久化是否真的落到磁盘。false 表示本平台只有内存兜底。
  bool get storagePersistent => LocalStore.instance.persistent;

  List<LibraryItem> of(LibraryKind kind) =>
      List<LibraryItem>.unmodifiable(_data[kind] ?? <LibraryItem>[]);

  int count(LibraryKind kind) => (_data[kind] ?? <LibraryItem>[]).length;

  String keyOf(LibraryKind kind) {
    switch (kind) {
      case LibraryKind.favorites:
        return _keyFavorites;
      case LibraryKind.history:
        return _keyHistory;
      case LibraryKind.watchLater:
        return _keyWatchLater;
    }
  }

  int limitOf(LibraryKind kind) =>
      kind == LibraryKind.history ? _maxHistory : _maxLists;

  Future<void> load() async {
    await LocalStore.instance.init();
    final store = LocalStore.instance;
    for (final kind in LibraryKind.values) {
      final raw = store.getString(keyOf(kind));
      // 重构前这里只在有值时覆盖 _data，导致「清空后再 load」会把内存里的
      // 旧列表重新写回，看起来像清空无效。现在无论有无数据都先重置。
      _data[kind] = <LibraryItem>[];
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = json.decode(raw);
        if (decoded is! List) continue;
        _data[kind] = decoded
            .map((e) => LibraryItem.fromJson(e))
            .where((item) => item.video.bvid.isNotEmpty)
            .toList();
      } catch (_) {
        // 单条列表数据损坏时跳过该列表，不让整个 App 起不来
        _data[kind] = <LibraryItem>[];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  bool has(LibraryKind kind, String bvid) =>
      (_data[kind] ?? <LibraryItem>[]).any((e) => e.video.bvid == bvid);

  bool isFavorite(String bvid) => has(LibraryKind.favorites, bvid);
  bool inWatchLater(String bvid) => has(LibraryKind.watchLater, bvid);

  Future<void> _persist(LibraryKind kind) async {
    await LocalStore.instance.setString(
      keyOf(kind),
      json.encode(_data[kind]!.map((e) => e.toJson()).toList()),
    );
  }

  void _insert(LibraryKind kind, Video video) {
    final list = _data[kind]!;
    list.removeWhere((e) => e.video.bvid == video.bvid);
    list.insert(
        0,
        LibraryItem(
          video: video,
          addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ));
    if (list.length > limitOf(kind)) {
      _data[kind] = list.sublist(0, limitOf(kind));
    }
  }

  Future<void> toggle(LibraryKind kind, Video video) async {
    if (has(kind, video.bvid)) {
      await remove(kind, video.bvid);
    } else {
      _insert(kind, video);
      notifyListeners();
      await _persist(kind);
    }
  }

  Future<void> addHistory(Video video) async {
    _insert(LibraryKind.history, video);
    notifyListeners();
    await _persist(LibraryKind.history);
  }

  Future<void> remove(LibraryKind kind, String bvid) async {
    _data[kind]!.removeWhere((e) => e.video.bvid == bvid);
    notifyListeners();
    await _persist(kind);
  }

  Future<void> clear(LibraryKind kind) async {
    _data[kind] = <LibraryItem>[];
    notifyListeners();
    await _persist(kind);
  }
}
