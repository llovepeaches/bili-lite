import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../account/account_card.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部本地数据？'),
        content: const Text('收藏、历史、稍后再看将被全部删除，不可撤销。主题设置不受影响。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(primary: AppColors.pink),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    for (final kind in LibraryKind.values) {
      await library.clear(kind);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('本地数据已清空'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSub
        : AppColors.lightSub;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        flexibleSpace: const GlassBar(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          // 外观
          _Card(
            title: '外观',
            children: <Widget>[
              AnimatedBuilder(
                animation: appState,
                builder: (_, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('当前：${appState.themeLabel}',
                        style: TextStyle(fontSize: 12, color: sub)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _themeChip('跟随系统', ThemeMode.system),
                        _themeChip('浅色', ThemeMode.light),
                        _themeChip('深色', ThemeMode.dark),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 液态玻璃
          _Card(
            title: '液态玻璃',
            children: <Widget>[
              AnimatedBuilder(
                animation: appState,
                builder: (_, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text('玻璃材质',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: appState.glassEnabled,
                          activeColor: AppColors.pink,
                          onChanged: (v) => appState.setGlassEnabled(v),
                        ),
                      ],
                    ),
                    Text(
                        '当前：${appState.glassEnabled ? appState.glassStrengthLabel : '已关闭'}',
                        style: TextStyle(fontSize: 11.5, color: sub)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _strengthChip('轻微', 0.45),
                        _strengthChip('标准', 0.75),
                        _strengthChip('浓郁', 1.0),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('材质（对应 iOS 26.1 的 Clear / Tinted）',
                        style: TextStyle(fontSize: 12, color: sub)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _materialChip('通透 Clear', false),
                        _materialChip('着色 Tinted', true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text('动态光晕',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: appState.glassEnabled && appState.glassMotion,
                          activeColor: AppColors.pink,
                          onChanged: appState.glassEnabled
                              ? (v) => appState.setGlassMotion(v)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'iOS 26 式透镜材质：内部近乎全透，靠沿边缘的折射亮环、色散与镜面亮斑定义形状；'
                      '通透档最接近原生观感，着色档抬高不透明度以提升文字可读性。'
                      '低配设备或浏览器可关闭材质与光晕以提升流畅度，设置保存在本机。',
                      style: TextStyle(fontSize: 11, color: sub, height: 1.55),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 服务状态
          _Card(
            title: '数据服务',
            children: <Widget>[
              AnimatedBuilder(
                animation: appState,
                builder: (_, __) {
                  final h = appState.health;
                  final connected = appState.serviceError.isEmpty && h != null;
                  final degraded = h?.mockMode == true;
                  return Column(
                    children: <Widget>[
                      _row('连接状态',
                          connected
                              ? (degraded ? '已降级 · 离线快照' : '已连接 B 站')
                              : '未连接',
                          valueColor: connected && !degraded
                              ? const Color(0xFF34B27B)
                              : const Color(0xFFE9A23B)),
                      _row('连接方式',
                          ApiConfig.direct
                              ? '原生直连 B 站公开接口'
                              : (ApiConfig.offline
                                  ? '纯离线（不发网络请求）'
                                  : '同源 BFF 代理')),
                      _row('服务地址', ApiConfig.displayBase),
                      _row('访客身份', h?.identity ?? '—'),
                      _row('数据模式',
                          degraded ? '离线快照' : 'B 站实时接口 + 自动降级'),
                      _row('缓存条目', '${h?.cacheEntries ?? 0} 条'),
                      _row('快照日期', h?.snapshotAt ?? '—'),
                      _row('服务版本', 'v${h?.version ?? '1.0.0'}'),
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
          ),
          const SizedBox(height: 14),

          // 本地数据
          _Card(
            title: '本地数据',
            children: <Widget>[
              AnimatedBuilder(
                animation: library,
                builder: (_, __) => Column(
                  children: <Widget>[
                    _row('收藏', '${library.count(LibraryKind.favorites)} 条'),
                    _row('观看历史', '${library.count(LibraryKind.history)} 条'),
                    _row('稍后再看', '${library.count(LibraryKind.watchLater)} 条'),
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
          ),
          const SizedBox(height: 14),

          // B 站账号（官方 OAuth 2.0，凭证本地持久化）
          const AccountCard(),
          const SizedBox(height: 14),

          // 账号与数据边界
          _Card(
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
          _Card(
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
              _row('App 版本', '1.2.0'),
              _row('支持平台', 'Android / iOS / Web / Windows / macOS / Linux'),
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
          ),
        ],
      ),
    );
  }

  Widget _themeChip(String label, ThemeMode mode) {
    final selected = appState.themeMode == mode;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: () => appState.setThemeMode(mode),
    );
  }

  Widget _strengthChip(String label, double value) {
    final selected = appState.glassEnabled && appState.glassStrength == value;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: appState.glassEnabled
          ? () => appState.setGlassStrength(value)
          : null,
    );
  }

  Widget _materialChip(String label, bool tinted) {
    final selected = appState.glassEnabled && appState.glassTinted == tinted;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: appState.glassEnabled
          ? () => appState.setGlassTinted(tinted)
          : null,
    );
  }
}

Widget _row(String label, String value, {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
            width: 84,
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.lightSub))),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12.5, color: valueColor),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(title: title),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
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
