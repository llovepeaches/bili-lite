import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/glass.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';

/// 设置页里「数据服务 / 本地数据 / 关于」三块内容。
///
/// 它们与外观、界面区块一样都是独立设置卡，`settings_view.dart`
/// 只保留页面骨架与区块编排；说明型文案已移除。
class ServiceSection extends StatelessWidget {
  const ServiceSection({Key? key, required this.controller}) : super(key: key);

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return SettingsCard(
      title: '数据服务',
      storageKey: 'bili_lite_settings_service',
      children: <Widget>[
        AnimatedBuilder(
          animation: appState,
          builder: (_, __) {
            final h = appState.health;
            return Column(
              children: <Widget>[
                SettingsRow(
                  '连接状态',
                  controller.connectionLabel,
                  valueColor: controller.connected && !controller.degraded
                      ? AppStatus.success
                      : AppStatus.warning,
                ),
                SettingsRow('连接方式', controller.connectionMode),
                SettingsRow('服务地址', controller.serviceBase),
                SettingsRow('访客身份', h?.identity ?? '—'),
                SettingsRow(
                    '数据模式', controller.degraded ? '离线快照' : 'B 站实时接口 + 自动降级'),
                SettingsRow('缓存条目', '${h?.cacheEntries ?? 0} 条'),
                SettingsRow('快照日期', h?.snapshotAt ?? '—'),
                SettingsRow('服务版本', 'v${h?.version ?? '1.0.0'}'),
                if (appState.serviceError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(appState.serviceError,
                        style: TextStyle(fontSize: 11, color: sub)),
                  ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassChip(
                    label: '重新检测',
                    icon: Icons.refresh_rounded,
                    tint: AppColors.pink,
                    radius: 11,
                    onTap: () => appState.refreshServerInfo(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class LocalDataSection extends StatelessWidget {
  const LocalDataSection({Key? key, required this.onClearAll})
      : super(key: key);

  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: '本地数据',
      storageKey: 'bili_lite_settings_local',
      children: <Widget>[
        AnimatedBuilder(
          animation: library,
          builder: (_, __) => Column(
            children: <Widget>[
              SettingsRow('收藏', '${library.count(LibraryKind.favorites)} 条'),
              SettingsRow('观看历史', '${library.count(LibraryKind.history)} 条'),
              SettingsRow('稍后再看', '${library.count(LibraryKind.watchLater)} 条'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: GlassChip(
                  label: '清空全部本地数据',
                  icon: Icons.delete_outline_rounded,
                  tint: AppColors.pink,
                  radius: 11,
                  onTap: onClearAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 关于：只保留版本与平台信息，不再展示说明型长文。
class AboutSection extends StatelessWidget {
  const AboutSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: '关于',
      collapsible: false,
      children: const <Widget>[
        SettingsRow('App 版本', kAppVersionLabel),
        SettingsRow('支持平台', 'Android / iOS / Web / Windows / macOS / Linux'),
      ],
    );
  }
}
