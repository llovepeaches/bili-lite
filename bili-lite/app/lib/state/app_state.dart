import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import '../data/models.dart';

/// 全局轻量状态：主题、分区表、服务健康信息。
/// 不引入 Provider/Riverpod，用 ChangeNotifier + AnimatedBuilder 即可覆盖全部场景。
class AppState extends ChangeNotifier {
  AppState({BiliRepository? repository})
      : _repo = repository ?? BiliRepository();

  final BiliRepository _repo;

  static const String _themeKey = 'bili_lite_theme_mode';
  static const String _glassKey = 'bili_lite_glass_enabled';
  static const String _glassStrengthKey = 'bili_lite_glass_strength';
  static const String _glassMotionKey = 'bili_lite_glass_motion';
  static const String _glassTintedKey = 'bili_lite_glass_tinted';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // ---- 液态玻璃外观 ----
  bool _glassEnabled = true;
  bool get glassEnabled => _glassEnabled;

  /// 0.45 轻微 / 0.75 标准 / 1.0 浓郁
  double _glassStrength = 0.75;
  double get glassStrength => _glassStrength;

  bool _glassMotion = true;
  bool get glassMotion => _glassMotion;

  /// iOS 26.1 材质：false = 通透 Clear（默认），true = 着色 Tinted。
  bool _glassTinted = false;
  bool get glassTinted => _glassTinted;

  List<Partition> _partitions = const <Partition>[
    Partition(rid: 0, name: '全站'),
    Partition(rid: 1, name: '动画'),
    Partition(rid: 3, name: '音乐'),
    Partition(rid: 4, name: '游戏'),
    Partition(rid: 36, name: '知识'),
    Partition(rid: 188, name: '科技'),
    Partition(rid: 160, name: '生活'),
    Partition(rid: 211, name: '美食'),
    Partition(rid: 234, name: '运动'),
    Partition(rid: 181, name: '影视'),
    Partition(rid: 119, name: '鬼畜'),
    Partition(rid: 5, name: '娱乐'),
  ];
  List<Partition> get partitions => _partitions;

  HealthInfo? _health;
  HealthInfo? get health => _health;

  String _serviceError = '';
  String get serviceError => _serviceError;

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeKey);
      if (saved == 'light') _themeMode = ThemeMode.light;
      if (saved == 'dark') _themeMode = ThemeMode.dark;
      _glassEnabled = prefs.getBool(_glassKey) ?? true;
      final strength = prefs.getDouble(_glassStrengthKey);
      if (strength != null && strength >= 0.3 && strength <= 1.0) {
        _glassStrength = strength;
      }
      _glassMotion = prefs.getBool(_glassMotionKey) ?? true;
      _glassTinted = prefs.getBool(_glassTintedKey) ?? false;
    } catch (_) {
      /* 存储不可用时保持默认 */
    }
    _initialized = true;
    notifyListeners();
    // 服务探测不阻塞首屏：失败时页面仍可用本地兜底数据
    refreshServerInfo();
  }

  Future<void> refreshServerInfo() async {
    try {
      final meta = await _repo.meta();
      if (meta.data.partitions.isNotEmpty) _partitions = meta.data.partitions;
      _serviceError = '';
    } catch (_) {
      // 分区表有本地兜底，不视为致命错误
    }
    try {
      final h = await _repo.health();
      _health = h.data;
      _serviceError = '';
    } catch (e) {
      _serviceError = e.toString();
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _themeKey, mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system');
    } catch (_) {}
  }

  Future<void> setGlassEnabled(bool enabled) async {
    _glassEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_glassKey, enabled);
    } catch (_) {}
  }

  Future<void> setGlassStrength(double strength) async {
    _glassStrength = strength;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_glassStrengthKey, strength);
    } catch (_) {}
  }

  Future<void> setGlassMotion(bool enabled) async {
    _glassMotion = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_glassMotionKey, enabled);
    } catch (_) {}
  }

  Future<void> setGlassTinted(bool tinted) async {
    _glassTinted = tinted;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_glassTintedKey, tinted);
    } catch (_) {}
  }

  String get glassStrengthLabel {
    if (_glassStrength < 0.6) return '轻微';
    if (_glassStrength < 0.9) return '标准';
    return '浓郁';
  }

  String get themeLabel {
    switch (_themeMode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      default:
        return '跟随系统';
    }
  }
}
