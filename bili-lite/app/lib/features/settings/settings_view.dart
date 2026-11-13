import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/glass.dart';
import '../account/account_view.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';

/// 设置页（视图层）。
///
/// 重构前这一个文件接近 500 行，把「外观 / 液态玻璃 / 数据服务 / 本地数据」
/// 四组完全独立的设置挤在一起，还混着业务动作。现在：
///   * 交互与派生状态 → [SettingsController]
///   * 外观与玻璃设置 → `settings_sections.dart` 里的分区组件
///   * 本文件只负责页面骨架与区块编排
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
    final sub = context.subTextColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        flexibleSpace: const GlassBar(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          const AppearanceSection(),
          const SizedBox(height: 14),
          const InterfaceSection(),
          const SizedBox(height: 14),
          const GlassSection(),
          const SizedBox(height: 14),
          _serviceSection(sub),
          const SizedBox(height: 14),
          _dataSection(),
          const SizedBox(height: 14),

          // B 站账号（官方 OAuth 2.0，凭证本地持久化）
          const AccountCard(),
          const SizedBox(height: 14),

          // 账号与数据边界
          SettingsCard(
            title: '账号与数据边界',
            children: const <Widget>[
              _Paragraph(
                '登录采用 B 站开放平台官方 OAuth 2.0 授权码流程：在官方授权页完成授权，'
                '由授权服务端用 client_secret 换取 access_token，客户端领取后把凭证保存在本机。'
                '全程不接触账号密码，也不读取 Cookie、SESSDATA 或 bili_jct——'
                '抓取 Web 登录态复用这些字段不是官方登录方式。'),
              SizedBox(height: 10),
              _Paragraph(
                'client_secret 只存在于授权服务端的环境变量里，不写入客户端、安装包、'
                '日志或 Git；授权码 code 也不落客户端。本机保存的 token 仅用于调用'
                '开放平台已授权的只读接口（当前为 USER_INFO），不上传、不共享。'),
              SizedBox(height: 10),
              _Paragraph(
                '官方已开放的 scope 面向创作者与账号侧（USER_INFO、USER_DATA、'
                'ARC_BASE、ARC_DATA、ATC_BASE、ATC_DATA 等），不包含观看侧的'
                '评论、投币、点赞接口。因此这些互动仍通过「评论 / 投币」入口在官方客户端完成，'
                '本应用不会用 OAuth token 去调用未开放的写接口，也不会逆向 WBI 签名。'),
              SizedBox(height: 10),
              _Paragraph(
                '播放使用 B 站官方站外外链播放器（player.bilibili.com）：只传 BV 号与分 P，'
                '不解析播放地址、不接触视频流、不把 OAuth 登录态注入播放器；'
                '登录态、清晰度与版权控制均由官方域名负责。'),
              SizedBox(height: 10),
              _Paragraph(
                '收藏、观看历史、稍后再看、搜索历史与外观设置继续留在本机，不关联账号。'
                '「退出登录」只清除本机凭证；如需在 B 站侧彻底解除授权，'
                '请到 B 站账号设置的授权管理中操作。'),
            ],
          ),
          const SizedBox(height: 14),

          // 关于
          _aboutSection(sub),
        ],
      ),
    );
  }

  Widget _serviceSection(Color sub) {
    return SettingsCard(
      title: '数据服务',
      children: <Widget>[
        AnimatedBuilder(
          animation: appState,
          builder: (_, __) {
            final h = appState.health;
            return Column(
              children: <Widget>[
                SettingsRow(
                  '连接状态',
                  _controller.connectionLabel,
                  valueColor: _controller.connected && !_controller.degraded
                      ? AppStatus.success
                      : AppStatus.warning,
                ),
                SettingsRow('连接方式', _controller.connectionMode),
                SettingsRow('服务地址', _controller.serviceBase),
                SettingsRow('访客身份', h?.identity ?? '—'),
                SettingsRow(
                    '数据模式',
                    _controller.degraded
                        ? '离线快照'
                        : 'B 站实时接口 + 自动降级'),
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

  Widget _dataSection() {
    return SettingsCard(
      title: '本地数据',
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
                  onTap: _clearAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aboutSection(Color sub) {
    return SettingsCard(
      title: '关于',
      children: <Widget>[
        const _Paragraph(
          'Bili Lite 是一个基于哔哩哔哩公开 Web 数据的非官方第三方客户端，'
          '用于学习与个人使用，与哔哩哔哩官方无任何关联。'),
        const SizedBox(height: 10),
        const _Paragraph(
          '设计目标是「简洁」：只保留推荐、热门、排行榜、搜索、详情与评论，'
          '播放交由 B 站官方外链播放器、不加载广告、不做个性化信息流追踪。'),
        const SizedBox(height: 10),
        const _Paragraph(
          '收藏、历史、稍后再看与搜索历史全部保存在本机，不上传任何服务器，'
          '浏览内容无需登录；B 站账号登录仅用于官方 OAuth 授权与展示用户公开资料。'),
        const SizedBox(height: 10),
        const SettingsRow('App 版本', '1.4.0'),
        const SettingsRow('支持平台', 'Android / iOS / Web / Windows / macOS / Linux'),
        const SizedBox(height: 12),
        GlassPanel(
          radius: 14,
          padding: const EdgeInsets.all(11),
          tint: AppColors.pink.withOpacity(0.10),
          showSheen: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.pink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '请遵守哔哩哔哩用户协议与 robots 规则，勿用于商业用途或高频抓取；'
                  '接口可能随官方调整而失效，服务端已做缓存与离线降级。',
                  style: TextStyle(fontSize: 11.5, color: sub, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 12.5, height: 1.65));
  }
}
