import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import 'player_controller.dart';
import 'player_sections.dart';

/// 应用内播放页。
///
/// 与上一版的区别：这一版**真的在应用里播放**。
///   * 画面：原生端用 `video_player`（Texture），Web 端用同源 `<video>`；
///   * 弹幕：从 `/api/danmaku` 拉取，按时间轴铺轨道，叠在画面上；
///   * 官方外链播放器降级为「备用入口」，不再是唯一方案。
///
/// 播放地址统一走 BFF 的 `/api/stream`：B 站 CDN 有 referer 防盗链，
/// 浏览器与部分原生环境直连会 403，服务端统一注入请求头最省事。
///
/// 播放区、控制条、弹幕设置与信息卡在 `player_sections.dart`；
/// 本文件只保留页面状态、AppBar 与区块编排。
class PlayerPage extends StatefulWidget {
  const PlayerPage({Key? key, required this.video, this.page = 1})
      : super(key: key);

  final Video video;
  final int page;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController _controller;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController(
      bvid: widget.video.bvid,
      cid: widget.video.cid,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.attachTicker();
      _controller.load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await canLaunchUrl(uri)
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无法打开外部链接'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('无法打开外部链接'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => IconButton(
              tooltip: _controller.danmakuEnabled ? '关闭弹幕' : '开启弹幕',
              onPressed: _controller.toggleDanmaku,
              icon: Icon(
                _controller.danmakuEnabled
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_rounded,
                color: _controller.danmakuEnabled ? AppColors.pink : sub,
                size: 20,
              ),
            ),
          ),
          IconButton(
            tooltip: '弹幕设置',
            onPressed: () => setState(() => _showSettings = !_showSettings),
            icon: Icon(Icons.tune_rounded, color: sub, size: 20),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            PlayerStage(controller: _controller),
            const SizedBox(height: 14),
            PlayerControls(
              controller: _controller,
              onQualityHint: () => _showQualityHint(context),
            ),
            if (_showSettings) ...<Widget>[
              const SizedBox(height: 12),
              PlayerDanmakuSettings(controller: _controller),
            ],
            const SizedBox(height: 14),
            PlayerInfoCard(video: widget.video, onLaunch: _launch),
          ],
        ),
      ),
    );
  }

  void _showQualityHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('当前清晰度：${_controller.qualityLabel}（默认 720P）'),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

/// 供测试检查当前是否走代理通道。
bool get playerUsesProxy => kIsWeb || ApiConfig.direct == false;
