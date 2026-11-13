import 'package:flutter/material.dart';

import '../core/partitions.dart';
import '../core/storage.dart';
import '../data/models.dart';
import '../data/repository.dart';

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

  /// 分区表。默认取单一数据源 [BiliPartitions]，联网成功后由服务端 meta 覆盖。
  List<Partition> _partitions = BiliPartitions.items;
  List<Partition> get partitions => _partitions;

  HealthInfo? _health;
  HealthInfo? get health => _health;

  String _serviceError = '';
  String get serviceError => _serviceError;

  bool _initialized = false;
  bool get initialized => _initialized;

  /// 本地持久化是否真的落到磁盘。false 表示本平台只有内存兜底。
  bool get storagePersistent => LocalStore.instance.persistent;

  Future<void> init() async {
    await LocalStore.instance.init();
    final store = LocalStore.instance;

    final saved = store.getString(_themeKey);
    if (saved == 'light') _themeMode = ThemeMode.light;
    if (saved == 'dark') _themeMode = ThemeMode.dark;
    _glassEnabled = store.getBool(_glassKey) ?? true;
    final strength = store.getDouble(_glassStrengthKey);
    if (strength != null && strength >= 0.3 && strength <= 1.0) {
      _glassStrength = strength;
    }
    _glassMotion = store.getBool(_glassMotionKey) ?? true;
    _glassTinted = store.getBool(_glassTintedKey) ?? false;

    _initialized = true;
    notifyListeners();
    // 服务探测不阻塞首屏：失败时页面仍可用本地兜底数据
    refreshServerInfo();
  }

  Future<void> refreshServerInfo() async {
    try {
      final meta = await _repo.meta();
      if (meta.data.partitions.isNotEmpty) {
        _partitions = meta.data.partitions;
      }
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
    await LocalStore.instance.setString(
      _themeKey,
      mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system',
    );
  }

  Future<void> setGlassEnabled(bool enabled) async {
    _glassEnabled = enabled;
    notifyListeners();
    await LocalStore.instance.setBool(_glassKey, enabled);
  }

  Future<void> setGlassStrength(double strength) async {
    _glassStrength = strength;
    notifyListeners();
    await LocalStore.instance.setDouble(_glassStrengthKey, strength);
  }

  Future<void> setGlassMotion(bool enabled) async {
    _glassMotion = enabled;
    notifyListeners();
    await LocalStore.instance.setBool(_glassMotionKey, enabled);
  }

  Future<void> setGlassTinted(bool tinted) async {
    _glassTinted = tinted;
    notifyListeners();
    await LocalStore.instance.setBool(_glassTintedKey, tinted);
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
