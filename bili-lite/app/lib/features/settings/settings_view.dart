import 'package:flutter/material.dart';

import '../../widgets/app_page_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../account/account_view.dart';
import 'settings_content_sections.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';
import 'update_section.dart';

/// 设置页（视图层）。
///
/// 交互与派生状态在 [SettingsController]；外观、界面、数据服务、本地数据、
/// 账号与关于各自是独立区块组件。本文件只负责页面骨架与区块编排，
/// 说明型文案已移除，仅保留可操作的设置项与状态信息。
class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clearAll() async {
    final ok = await showConfirmDialog(
      context,
      title: '清空全部本地数据？',
      message: '收藏、历史、稍后再看与搜索历史将被全部删除，不可撤销。主题设置不受影响。',
      confirmLabel: '清空',
    );
    if (!ok) return;
    await _controller.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('本地数据已清空'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: const Text('设置'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          const AppearanceSection(),
          const SizedBox(height: 14),
          const InterfaceSection(),
          const SizedBox(height: 14),
          ServiceSection(controller: _controller),
          const SizedBox(height: 14),
          LocalDataSection(onClearAll: _clearAll),
          const SizedBox(height: 14),

          // B 站账号（官方 OAuth 2.0，凭证本地持久化）
          const AccountCard(),
          const SizedBox(height: 14),

          // 版本与更新检查（v0.1.0 起）
          const UpdateSection(),
          const SizedBox(height: 14),

          // 关于：只保留版本与平台信息
          const AboutSection(),
        ],
      ),
    );
  }
}
