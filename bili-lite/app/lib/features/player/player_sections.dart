import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/bili_player.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/glass.dart';
import 'danmaku_overlay.dart';
import 'player_controller.dart';

/// 播放区：画面 + 弹幕层。
class PlayerStage extends StatelessWidget {
  const PlayerStage({Key? key, required this.controller}) : super(key: key);

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
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
                  : PlayerStagePlaceholder(
                      error: controller.error,
                      onRetry: controller.load,
                    ),
            ),
            // 原生端弹幕画在 Flutter 画布上（Texture 之上）。
            // Web 端视频是 DOM 元素，弹幕由 video_surface_web 在同层绘制。
            if (!kIsWeb)
              DanmakuOverlay(
                source: controller.danmaku,
                position: controller.position,
                enabled: controller.danmakuEnabled,
              ),
            if (controller.loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (controller.hasVideo &&
                !controller.isPlaying &&
                !controller.loading)
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
}

class PlayerStagePlaceholder extends StatelessWidget {
  const PlayerStagePlaceholder({
    Key? key,
    required this.error,
    required this.onRetry,
  }) : super(key: key);

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 播放控制条：进度、播放/暂停、时间。
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    Key? key,
    required this.controller,
    required this.onQualityHint,
  }) : super(key: key);

  final PlayerController controller;
  final VoidCallback onQualityHint;

  @override
  Widget build(BuildContext context) {
    final c = controller;
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
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: fraction,
                    onChanged: total <= 0 ? null : (v) => c.seekFraction(v),
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
                  onTap: onQualityHint,
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
}

class PlayerDanmakuSettings extends StatelessWidget {
  const PlayerDanmakuSettings({Key? key, required this.controller})
      : super(key: key);

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
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
          _SliderRow(
              label: '不透明度',
              value: c.danmakuOpacity,
              onChanged: c.setDanmakuOpacity),
          _SliderRow(
              label: '字号',
              value: c.danmakuFontScale,
              onChanged: c.setDanmakuFontScale),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
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
}

class PlayerInfoCard extends StatelessWidget {
  const PlayerInfoCard({
    Key? key,
    required this.video,
    required this.onLaunch,
  }) : super(key: key);

  final Video video;
  final Future<void> Function(String url) onLaunch;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = context.subTextColor;
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
                onTap: () => onLaunch(BiliPlayer.officialPage(video.bvid)),
              ),
              GlassChip(
                label: '官方播放器文档',
                icon: Icons.description_outlined,
                radius: 11,
                onTap: () => onLaunch(BiliPlayer.docsUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
