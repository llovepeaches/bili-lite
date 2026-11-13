import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化的统一门面。
///
/// 之前 AppState / LibraryState / SearchPage / AuthSession 各自写了一遍
/// `SharedPreferences.getInstance()` + try/catch，逻辑重复且错误处理不一致。
/// 这里收敛成一个入口，并明确回答一个跨端问题：
///
/// **本地存储在哪些端真的可用？**
///
/// shared_preferences 2.1.x 是 federated 插件，六个端全部有原生实现：
/// Android → shared_preferences_android
/// iOS / macOS → shared_preferences_foundation
/// Windows → shared_preferences_windows
/// Linux → shared_preferences_linux
/// Web → shared_preferences_web
///
/// 早期 2.0.x 只有 Android / iOS / Web，Windows / Linux / macOS 会因为
/// `MissingPluginException` 静默退化为「不持久化」。pubspec 里的版本下限
/// 之前写成 `^2.0.15`，允许解析到 2.0.x——这才是 Windows 上本地数据
/// 「存不住」的真正原因，而不是「平台不支持」。
///
/// 因此：
///   * pubspec 约束收紧到 `^2.1.0`，保证六端都有原生实现；
///   * 本类在初始化时**主动探测**一次，把结果如实暴露给 UI；
///   * 探测失败时降级为内存存储（本会话内有效），而不是让上层各自静默失败。
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  SharedPreferences? _prefs;

  /// 初始化失败时使用的内存兜底，保证同一会话内功能可用。
  final Map<String, Object> _memory = <String, Object>{};

  bool _initialized = false;

  /// 平台是否具备真正的原生持久化能力。
  /// false 表示当前只能在本会话内保存（刷新 / 重启后丢失）。
  bool persistent = true;

  /// 探测失败时的原因，用于在设置页如实告知用户。
  String? unavailableReason;

  bool get initialized => _initialized;

  /// 初始化并探测原生持久化能力。整个 App 只需调用一次。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      persistent = true;
      unavailableReason = null;
    } catch (e) {
      _prefs = null;
      persistent = false;
      unavailableReason = '当前平台的本地存储插件不可用：$e';
    }
  }

  SharedPreferences? get _p => _prefs;

  // ------------------------------------------------------------------
  // 读
  // ------------------------------------------------------------------

  String? getString(String key) {
    final p = _p;
    if (p != null) {
      try {
        return p.getString(key);
      } catch (_) {
        // 落到内存兜底
      }
    }
    final v = _memory[key];
    return v is String ? v : null;
  }

  int? getInt(String key) {
    final p = _p;
    if (p != null) {
      try {
        return p.getInt(key);
      } catch (_) {}
    }
    final v = _memory[key];
    return v is int ? v : null;
  }

  bool? getBool(String key) {
    final p = _p;
    if (p != null) {
      try {
        return p.getBool(key);
      } catch (_) {}
    }
    final v = _memory[key];
    return v is bool ? v : null;
  }

  double? getDouble(String key) {
    final p = _p;
    if (p != null) {
      try {
        return p.getDouble(key);
      } catch (_) {}
    }
    final v = _memory[key];
    return v is double ? v : null;
  }

  List<String>? getStringList(String key) {
    final p = _p;
    if (p != null) {
      try {
        return p.getStringList(key);
      } catch (_) {}
    }
    final v = _memory[key];
    return v is List<String> ? v : null;
  }

  /// 读取一段 JSON 数组字符串并解析成字符串列表。
  List<String> getStringListFromJson(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const <String>[];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      // 数据损坏时按空列表处理，不让 App 起不来
      return const <String>[];
    }
  }

  /// 写入字符串列表（以 JSON 数组存储）。
  Future<bool> setStringListAsJson(String key, List<String> value) =>
      setString(key, json.encode(value));

  // ------------------------------------------------------------------
  // 写
  // ------------------------------------------------------------------

  Future<bool> setString(String key, String value) async {
    _memory[key] = value;
    final p = _p;
    if (p == null) return false;
    try {
      return await p.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setInt(String key, int value) async {
    _memory[key] = value;
    final p = _p;
    if (p == null) return false;
    try {
      return await p.setInt(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setBool(String key, bool value) async {
    _memory[key] = value;
    final p = _p;
    if (p == null) return false;
    try {
      return await p.setBool(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDouble(String key, double value) async {
    _memory[key] = value;
    final p = _p;
    if (p == null) return false;
    try {
      return await p.setDouble(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setStringList(String key, List<String> value) async {
    _memory[key] = value;
    final p = _p;
    if (p == null) return false;
    try {
      return await p.setStringList(key, value);
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(String key) async {
    _memory.remove(key);
    final p = _p;
    if (p == null) return false;
    try {
      return await p.remove(key);
    } catch (_) {
      return false;
    }
  }
}
