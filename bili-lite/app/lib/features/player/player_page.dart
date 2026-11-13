import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/bili_player.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/glass.dart';
import 'danmaku_overlay.dart';
import 'player_controller.dart';

/// 应用内播放页。
///
/// 与上一版的区别：这一版**真的在应用里播放**。
///   * 画面：原生端用 `video_player`（Texture），Web 端用同源 `<video>`；
///   * 弹幕：从 `/api/danmaku` 拉取，按时间轴铺轨道，叠在画面上；
///   * 官方外链播放器降级为「备用入口」，不再是唯一方案。
///
/// 播放地址统一走 BFF 的 `/api/stream`：B 站 CDN 有 referer 防盗链，
/// 浏览器与部分原生环境直连会 403，服务端统一注入请求头最省事。
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
    final dark = Theme.of(context).brightness == Brightness.dark;
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
            _buildStage(context),
            const SizedBox(height: 14),
            _buildControls(context),
            if (_showSettings) ...<Widget>[
              const SizedBox(height: 12),
              _buildSettings(context),
            ],
            const SizedBox(height: 14),
            _buildInfo(context, sub, dark),
          ],
        ),
      ),
    );
  }

  /// 播放区：画面 + 弹幕层。
  Widget _buildStage(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: Colors.black,
              child: controller.hasVideo
                  ? GestureDetector(
                      // 原生控制条已隐藏，点画面即播放 / 暂停。
                      behavior: HitTestBehavior.opaque,
                      onTap: controller.togglePlay,
                      child: controller.surface.widget,
                    )
                  : _buildStagePlaceholder(context),
            ),
            // 原生端弹幕画在 Flutter 画布上（Texture 之上）。
            // Web 端视频是 DOM 元素，这个层会被挡住，
            // 所以 Web 端的弹幕由 video_surface_web 在同一层 DOM 里绘制。
            if (!kIsWeb)
              DanmakuOverlay(
                source: controller.danmaku,
                position: controller.position,
                enabled: controller.danmakuEnabled,
              ),
            if (controller.loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            // 暂停时给出明确的中央提示，避免「没在动」看起来像卡住。
            if (controller.hasVideo && !controller.isPlaying && !controller.loading)
              Center(
                child: GlassCircleButton(
                  icon: Icons.play_arrow_rounded,
                  size: 56,
                  onTap: controller.togglePlay,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStagePlaceholder(BuildContext context) {
    final error = _controller.error;
    final sub = context.subTextColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              error == null
                  ? Icons.play_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 40,
              color: error == null ? AppColors.pink : AppColors.pink,
            ),
            const SizedBox(height: 10),
            Text(
              error ?? '正在解析播放地址…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: sub, height: 1.5),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              GlassChip(
                label: '重试',
                icon: Icons.refresh_rounded,
                tint: AppColors.pink,
                onTap: _controller.load,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 播放控制条：进度、播放/暂停、时间。
  Widget _buildControls(BuildContext context) {
    final c = _controller;
    final total = c.duration.inMilliseconds;
    final current = c.position.inMilliseconds;
    final double fraction =
        total <= 0 ? 0 : (current / total).clamp(0.0, 1.0).toDouble();

    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                Fmt.duration(c.position.inSeconds),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: fraction,
                    onChanged: total <= 0
                        ? null
                        : (v) => c.seekFraction(v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Fmt.duration(c.duration.inSeconds),
                style: TextStyle(fontSize: 11, color: context.subTextColor),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              GlassChip(
                label: c.isPlaying ? '暂停' : '播放',
                icon: c.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tint: AppColors.pink,
                onTap: c.togglePlay,
              ),
              const SizedBox(width: 8),
              if (c.qualityLabel.isNotEmpty)
                GlassChip(
                  label: c.qualityLabel,
                  icon: Icons.high_quality_rounded,
                  onTap: () => _showQualityHint(context),
                ),
              const SizedBox(width: 8),
              GlassChip(
                label: '弹幕 ${c.danmakuCount}',
                icon: Icons.chat_bubble_outline_rounded,
                selected: c.danmakuEnabled,
                onTap: c.toggleDanmaku,
              ),
              const Spacer(),
              if (c.isPlaying)
                GlassChip(
                  label: '暂停',
                  icon: Icons.pause_circle_outline_rounded,
                  onTap: c.togglePlay,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(BuildContext context) {
    final c = _controller;
    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '弹幕设置',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkText
                  : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 8),
          _slider(context, '不透明度', c.danmakuOpacity, c.setDanmakuOpacity),
          _slider(context, '字号', c.danmakuFontScale, c.setDanmakuFontScale),
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    String label,
    double value,
    void Function(double) onChanged,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: context.subTextColor),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: label == '字号' ? 0.6 : 0.1,
            max: label == '字号' ? 2.0 : 1.0,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(1),
            style: TextStyle(fontSize: 11, color: context.subTextColor),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo(BuildContext context, Color sub, bool dark) {
    final video = widget.video;
    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            video.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: dark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${video.owner.name} · ${Fmt.compact(video.stat.view)} 播放 · '
            '${Fmt.compact(video.stat.danmaku)} 弹幕',
            style: TextStyle(fontSize: 11.5, color: sub),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GlassChip(
                label: '在官方站点打开',
                icon: Icons.open_in_new_rounded,
                tint: AppColors.pink,
                radius: 11,
                onTap: () => _launch(BiliPlayer.officialPage(video.bvid)),
              ),
              GlassChip(
                label: '官方播放器文档',
                icon: Icons.description_outlined,
                radius: 11,
                onTap: () => _launch(BiliPlayer.docsUrl),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '应用内播放由本机 BFF 代理视频流（/api/stream）并叠加本应用解析的弹幕；'
            '若上游因防盗链或网络原因拒绝取流，可切换到官方站点观看。',
            style: TextStyle(fontSize: 11, color: sub, height: 1.6),
          ),
        ],
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
