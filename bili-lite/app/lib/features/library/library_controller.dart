import 'package:flutter/material.dart';

import '../../state/library_state.dart';

/// 「我的」页的三个分区（收藏 / 历史 / 稍后再看）的元数据与切换逻辑。
///
/// 重构前这些常量与 tab 索引都写在 `library_page.dart` 的 State 里，
/// 视图与元数据混在一起。这里把「哪个 tab、叫什么、什么图标」抽出来，
/// 视图只负责渲染。
class LibraryController extends ChangeNotifier {
  /// tab 标题（页面 header 用）。
  static const List<String> titles = <String>[
    '收藏的视频',
    '观看历史',
    '稍后再看',
  ];

  /// tab 副标题。
  static const List<String> hints = <String>[
    '长按卡片可移除，数据仅保存在本机',
    '自动记录打开过的视频，最多保留 200 条',
    '想看但暂时没空？先存到这里',
  ];

  /// tab 图标。
  static const List<IconData> icons = <IconData>[
    Icons.favorite_border_rounded,
    Icons.history_rounded,
    Icons.watch_later_outlined,
  ];

  /// tab 文案（AppBar TabBar 用）。
  static const List<String> labels = <String>['收藏', '历史', '稍后再看'];

  int _active = 0;
  int get active => _active;

  LibraryKind get kind => LibraryKind.values[_active];

  void select(int index) {
    if (index == _active) return;
    _active = index;
    notifyListeners();
  }

  /// 空列表时的引导文案。
  String emptyHint() {
    switch (_active) {
      case 0:
        return '打开任意视频，点右上角的收藏按钮即可加入';
      case 1:
        return '浏览过的视频会自动出现在这里';
      default:
        return '在视频详情页点「稍后再看」即可加入';
    }
  }
}
