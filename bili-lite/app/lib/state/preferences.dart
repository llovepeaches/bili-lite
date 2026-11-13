import 'package:flutter/material.dart';

import '../core/card_style.dart';
import '../core/nav_section.dart';
import '../core/storage.dart';

/// 用户偏好：导航项顺序与显隐、卡片样式、滚动时是否隐藏底部 dock。
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
  static const String _keyHideDock = 'prefs.hideDockOnScroll';

  List<AppSection> _sections = <AppSection>[
    AppSection.home,
    AppSection.search,
    AppSection.library,
    AppSection.settings,
  ];
  CardStyle _cardStyle = CardStyle.immersive;
  bool _hideDockOnScroll = true;

  /// 当前导航项（按用户配置的顺序）。
  List<AppSection> get sections => List<AppSection>.unmodifiable(_sections);

  CardStyle get cardStyle => _cardStyle;

  /// 向下滚动时是否收起底部 dock（PiliPlus 的 hideBottomBar）。
  bool get hideDockOnScroll => _hideDockOnScroll;

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
    _hideDockOnScroll = LocalStore.instance.getBool(_keyHideDock) ?? true;
  }

  Future<void> setCardStyle(CardStyle style) async {
    if (_cardStyle == style) return;
    _cardStyle = style;
    notifyListeners();
    await LocalStore.instance.setString(_keyCardStyle, style.key);
  }

  Future<void> setHideDockOnScroll(bool value) async {
    if (_hideDockOnScroll == value) return;
    _hideDockOnScroll = value;
    notifyListeners();
    await LocalStore.instance.setBool(_keyHideDock, value);
  }

  /// 把某个分区移到新位置。
  Future<void> moveSection(AppSection section, int offset) async {
    final list = List<AppSection>.from(_sections);
    final index = list.indexOf(section);
    if (index < 0) return;
    final target = index + offset;
    if (target < 0 || target >= list.length) return;
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
      list.add(section);
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
      AppSection.search,
      AppSection.library,
      AppSection.settings,
    ];
    _cardStyle = CardStyle.immersive;
    _hideDockOnScroll = true;
    notifyListeners();
    await LocalStore.instance.remove(_keySections);
    await LocalStore.instance.remove(_keyCardStyle);
    await LocalStore.instance.remove(_keyHideDock);
  }
}
