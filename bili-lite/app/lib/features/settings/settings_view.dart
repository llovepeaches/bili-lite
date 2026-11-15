import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/glass.dart';
import '../account/account_view.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';
import 'update_section.dart';

/// 设置页（视图层）。
///
/// 重构前这一个文件接近 500 行，把「外观 / 液态玻璃 / 数据服务 / 本地数据」
/// 四组完全独立的设置挤在一起，还混着业务动作。现在：
///   * 交互与派生状态 → [SettingsController]
///   * 外观与玻璃设置 → `settings_sections.dart` 里的分区组件
///   * 版本与更新检查 → `update_section.dart`
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

          // 账号与数据边界：长说明默认折叠，标题下只留一行摘要
          SettingsCard(
            title: '账号与数据边界',
            initiallyCollapsed: true,
            storageKey: 'bili_lite_settings_boundary',
            collapsedHint: '四类 Web 登录 + 官方 OAuth 的凭证边界：'
                'Cookie 只存本机、密码不落盘、请求只发往 bilibili.com。',
            children: const <Widget>[
              _Paragraph(
                '本应用提供四类 B 站 Web 登录通道：扫码登录、账号密码登录、'
                '短信验证码登录、Cookie 登录；另有官方开放平台 OAuth 2.0 作为'
                '可选高级通道。前四类拿到的是同一份 B 站 Web 登录 Cookie'
                '（SESSDATA / bili_jct / DedeUserID 等），统一保存在本机，'
                '只发往 bilibili.com，不经过也不上传给任何第三方服务。'),
              SizedBox(height: 10),
              _Paragraph(
                '扫码登录是推荐方式：由 B 站直接下发登录态，不需要开放平台凭证。'
                '账号密码与短信验证码走 B 站 Web 登录接口，密码用 B 站下发的 '
                'RSA 公钥在本机加密后提交；这两类接口受 B 站极验滑块保护，'
                '遇到人机验证要求时本应用会如实提示，绝不伪造凭证或假装登录成功，'
                '此时请改用扫码登录，或在浏览器登录后复制 Cookie。'),
              SizedBox(height: 10),
              _Paragraph(
                'Cookie 登录由你手动粘贴浏览器中已登录的 Cookie，应用先用 nav '
                '接口校验有效后才写入本机；校验不通过绝不保存、绝不显示「已登录」。'
                '本机不保存账号密码、短信验证码，也不缓存 Cookie 到服务端。'
                '登录态存放在 shared_preferences（Web 为 localStorage），'
                '不是硬件加密存储，请勿在公用设备上使用。'),
              SizedBox(height: 10),
              _Paragraph(
                '官方 OAuth 通道由授权服务端用 client_secret 换取 access_token，'
                '客户端只领取 token 并保存在本机，全程不接触账号密码、不读取 Cookie。'
                'client_secret 只存在于服务端环境变量，不写入客户端、安装包、日志或 Git。'
                '官方已开放的 scope 不含观看侧评论 / 投币 / 点赞写接口，'
                '这些互动仍通过 B 站官方客户端完成；本应用不调用未开放写接口，'
                '也不逆向 WBI 签名。'),
              SizedBox(height: 10),
              _Paragraph(
                '播放使用 B 站官方站外外链播放器（player.bilibili.com）：只传 BV 号与分 P，'
                '不解析播放地址、不接触视频流、不把登录态注入播放器。'
                '收藏、观看历史、稍后再看、搜索历史与外观设置留在本机，不关联账号。'
                '「退出登录」只清除本机凭证；如需在 B 站侧彻底解除授权，'
                '请到 B 站账号设置的授权管理中操作。'),
            ],
          ),
          const SizedBox(height: 14),

          // 版本与更新检查（v0.1.0 起）
          const UpdateSection(),
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
      storageKey: 'bili_lite_settings_service',
      collapsedHint: '连接状态、服务地址、数据来源与缓存条目。',
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
      storageKey: 'bili_lite_settings_local',
      collapsedHint: '收藏 / 历史 / 稍后再看条目数与清空入口。',
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
      initiallyCollapsed: true,
      storageKey: 'bili_lite_settings_about',
      collapsedHint: '非官方第三方客户端，数据全部留在本机。展开查看设计说明与使用须知。',
      // 版本号与支持平台是高频查看信息，折叠时仍然常驻。
      alwaysVisible: const <Widget>[
        SettingsRow('App 版本', kAppVersionLabel),
        SettingsRow('支持平台', 'Android / iOS / Web / Windows / macOS / Linux'),
      ],
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
          '浏览内容无需登录；B 站账号登录仅用于展示用户公开资料与在本机保存'
          '登录态，不用于任何写入操作。'),
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
