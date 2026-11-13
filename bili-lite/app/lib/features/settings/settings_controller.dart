import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';

/// 设置页的动作控制器。
///
/// 重构前「清空全部本地数据」等操作直接写在 `settings_page.dart` 的 State
/// 里，视图文件同时承担「渲染」与「业务动作」两种职责，接近 500 行。
///
/// 这里把动作与派生状态抽到 controller：
///   * `clearAll()` —— 清空收藏 / 历史 / 稍后再看与搜索历史
///   * `connectionRows` —— 服务连接状态（是否已连接、是否降级、连接方式）
///   * `themeLabel` / `glassStrengthLabel` 等 —— 展示用的派生文案
class SettingsController extends ChangeNotifier {
  /// 清空全部本地数据（不含主题与外观设置）。
  /// 返回 true 表示确实执行了清空。
  Future<bool> clearAll() async {
    for (final kind in LibraryKind.values) {
      await library.clear(kind);
    }
    await searchHistory.clear();
    return true;
  }

  /// 服务是否已连通 B 站（未降级）。
  bool get connected =>
      appState.serviceError.isEmpty && appState.health != null;

  /// 服务是否处于离线快照降级状态。
  bool get degraded => appState.health?.mockMode == true;

  /// 连接状态文案。
  String get connectionLabel {
    if (!connected) return '未连接';
    return degraded ? '已降级 · 离线快照' : '已连接 B 站';
  }

  /// 连接方式文案。
  String get connectionMode {
    if (ApiConfig.direct) return '原生直连 B 站公开接口';
    if (ApiConfig.offline) return '纯离线（不发网络请求）';
    return '同源 BFF 代理';
  }

  /// 服务地址展示值。
  String get serviceBase => ApiConfig.displayBase;
}
