import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../player/player_controller.dart';
import '../player/player_fullscreen.dart';
import '../player/player_sections.dart';

/// 详情页内嵌播放器区块。
///
/// 视觉和责任都收敛在这里：画面 + 控制条 + 弹幕设置入口。
/// 点封面后由 [DetailController.startPlayback] 创建 [PlayerController]，
/// 本组件接手后续的状态展示与交互，不再 push 独立播放页。
///
/// [stageMaxHeight] 只约束 16:9 画面，控制条始终按自身高度排布，
/// 避免窄屏 / 横屏下整块播放器被 ConstrainedBox 压到溢出。
class DetailPlayer extends StatefulWidget {
  const DetailPlayer({
    Key? key,
    required this.controller,
    this.stageMaxHeight,
  }) : super(key: key);

  final PlayerController controller;

  /// 画面部分的最大高度；null 表示只按 16:9 自适应。
  final double? stageMaxHeight;

  @override
  State<DetailPlayer> createState() => _DetailPlayerState();
}

class _DetailPlayerState extends State<DetailPlayer> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        // 全屏页打开时内嵌只保留一个黑色占位：Web 端画面是真实 DOM 容器，
        // 同一时刻只允许一处 HtmlElementView 挂载，否则容器会被挪走。
        // 放在 AnimatedBuilder 内部，fullscreen 变化才能立刻撤下 / 恢复画面。
        Widget stage = widget.controller.fullscreen
            ? const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(color: Colors.black),
              )
            : PlayerStage(
                controller: widget.controller,
                onFullscreen: () =>
                    openFullscreenPlayer(context, widget.controller),
              );
        final maxHeight = widget.stageMaxHeight;
        if (maxHeight != null) {
          stage = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: stage,
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            stage,
            const SizedBox(height: 8),
            PlayerControls(
              controller: widget.controller,
              onQualityHint: _showQualityHint,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassChip(
                label: '弹幕设置',
                icon: Icons.tune_rounded,
                tint: AppColors.pink,
                radius: 10,
                selected: _showSettings,
                onTap: () => setState(() => _showSettings = !_showSettings),
              ),
            ),
            if (_showSettings) ...<Widget>[
              const SizedBox(height: 8),
              PlayerDanmakuSettings(controller: widget.controller),
            ],
          ],
        );
      },
    );
  }

  void _showQualityHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('当前清晰度：${widget.controller.qualityLabel}（默认 720P）'),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
