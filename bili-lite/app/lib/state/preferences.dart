import 'package:flutter/material.dart';

import '../core/card_style.dart';
import '../core/nav_section.dart';
import '../core/storage.dart';

/// 用户偏好：导航项顺序与显隐、卡片样式。
///
/// 全部走 `LocalStore` 门面，因此与其它本地数据共用同一套持久化约定
/// （设置页的「清空全部本地数据」也会一并清掉这里）。
///
/// 用 `ChangeNotifier` 而非顶层单例直接暴露字段：页面用 `AnimatedBuilder`
/// 只订阅自己关心的那一项，避免一个开关变化导致整页重建。
class AppPrefs extends ChangeNotifier {
  AppPrefs() {
    _load();
  }

  static const String _keySections = 'prefs.navSections';
  static const String _keyCardStyle = 'prefs.cardStyle';

  /// 全部可见入口（按用户配置的顺序，含独立入口）。
  List<AppSection> _sections = <AppSection>[
    AppSection.home,
    AppSection.library,
    AppSection.settings,
    AppSection.search,
  ];
  CardStyle _cardStyle = CardStyle.immersive;

  /// 当前导航项（按用户配置的顺序）。
  List<AppSection> get sections => List<AppSection>.unmodifiable(_sections);

  /// 底栏**胶囊内**的标签组：挤在同一条玻璃里的那几项，可排序。
  List<AppSection> get tabSections =>
      _sections.where((s) => !s.standalone).toList(growable: false);

  /// 底栏右侧的**独立入口**：从胶囊里分出来的那几项，固定在最右边。
  List<AppSection> get standaloneSections =>
      _sections.where((s) => s.standalone).toList(growable: false);

  CardStyle get cardStyle => _cardStyle;

  void _load() {
    final stored = LocalStore.instance.getStringList(_keySections);
    if (stored != null && stored.isNotEmpty) {
      final parsed = <AppSection>[];
      for (final key in stored) {
        final section = AppSection.fromKey(key);
        if (section != null && !parsed.contains(section)) parsed.add(section);
      }
      // 至少要留一个入口，否则壳层没有内容可显示。
      if (parsed.isNotEmpty) _sections = parsed;
    }
    _cardStyle = CardStyle.fromKey(LocalStore.instance.getString(_keyCardStyle) ?? '');
  }

  Future<void> setCardStyle(CardStyle style) async {
    if (_cardStyle == style) return;
    _cardStyle = style;
    notifyListeners();
    await LocalStore.instance.setString(_keyCardStyle, style.key);
  }

  /// 把某个分区在**同组内**上下移动。
  ///
  /// 标签组与独立入口是两套独立的顺序：独立入口固定在底栏右侧，
  /// 不参与标签组的排序，所以在标签之间移动不会把搜索拖进胶囊里。
  Future<void> moveSection(AppSection section, int offset) async {
    final list = List<AppSection>.from(_sections);
    final index = list.indexOf(section);
    if (index < 0) return;

    // 只在「同类」的下标之间移动。
    final sameKind = <int>[
      for (var i = 0; i < list.length; i++)
        if (list[i].standalone == section.standalone) i
    ];
    final positionInKind = sameKind.indexOf(index);
    if (positionInKind < 0) return;
    final targetPosition = positionInKind + offset;
    if (targetPosition < 0 || targetPosition >= sameKind.length) return;

    final target = sameKind[targetPosition];
    list.removeAt(index);
    list.insert(target, section);
    _sections = list;
    notifyListeners();
    await _persistSections();
  }

  /// 显示 / 隐藏某个分区。至少保留一个。
  Future<void> toggleSection(AppSection section) async {
    final list = List<AppSection>.from(_sections);
    if (list.contains(section)) {
      if (list.length <= 1) return;
      list.remove(section);
    } else {
      // 恢复时放回同类别的末尾，保持「独立入口在最右」的约定。
      final lastOfKind = list.lastIndexWhere((s) => s.standalone == section.standalone);
      if (lastOfKind < 0) {
        list.add(section);
      } else {
        list.insert(lastOfKind + 1, section);
      }
    }
    _sections = list;
    notifyListeners();
    await _persistSections();
  }

  Future<void> _persistSections() async {
    await LocalStore.instance.setStringList(
        _keySections, _sections.map((e) => e.key).toList());
  }

  /// 清空全部本地数据时一并重置（设置页「恢复默认」用）。
  Future<void> reset() async {
    _sections = <AppSection>[
      AppSection.home,
      AppSection.library,
      AppSection.settings,
      AppSection.search,
    ];
    _cardStyle = CardStyle.immersive;
    notifyListeners();
    await LocalStore.instance.remove(_keySections);
    await LocalStore.instance.remove(_keyCardStyle);
  }
}
