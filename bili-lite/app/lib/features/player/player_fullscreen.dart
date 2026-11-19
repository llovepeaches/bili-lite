import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass.dart';
import 'player_controller.dart';
import 'player_sections.dart';

/// 进入横屏 / 全屏播放。
///
/// 用一条独立路由承载，返回键（Android 物理键 / 手势）天然能退出；
/// 退出后由本函数在 finally 里恢复竖屏方向与系统 UI。
///
/// 内嵌播放器与全屏页共用同一个 [PlayerController]，但同一时刻只允许一处
/// 渲染 `surface.widget`：Web 端的画面是一个真实 DOM 容器，若被两个
/// HtmlElementView 同时挂载，容器会被从先挂载的位置挪走，内嵌画面就空了。
/// 所以进全屏前先 [PlayerController.setFullscreen] 让内嵌撤下画面，
/// pop 后再恢复。
Future<void> openFullscreenPlayer(
  BuildContext context,
  PlayerController controller,
) async {
  controller.setFullscreen(true);
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'fullscreen-player'),
        fullscreenDialog: true,
        builder: (_) => FullscreenPlayerPage(controller: controller),
      ),
    );
  } finally {
    controller.setFullscreen(false);
  }
}

/// 横屏全屏播放页：画面铺满、隐藏系统 UI、强制横屏方向。
///
/// Web 端没有「系统方向」概念，`SystemChrome` 调用整体跳过，页面照样铺满
/// 浏览器视口；桌面端即使抛 MissingPluginException 也只是没有方向，
/// 画面与弹幕设置仍可用。
class FullscreenPlayerPage extends StatefulWidget {
  const FullscreenPlayerPage({Key? key, required this.controller})
      : super(key: key);

  final PlayerController controller;

  @override
  State<FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<FullscreenPlayerPage> {
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    unawaited(_enterLandscape());
  }

  @override
  void dispose() {
    unawaited(_restoreOrientation());
    super.dispose();
  }

  Future<void> _enterLandscape() async {
    if (kIsWeb) return;
    try {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // 桌面端没有系统方向概念，忽略即可。
    }
  }

  Future<void> _restoreOrientation() async {
    if (kIsWeb) return;
    try {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // 同上：桌面端没有系统方向概念，忽略即可。
    }
  }

  void _showQualityHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('当前清晰度：${widget.controller.qualityLabel}（默认 720P）'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 全屏时画面直接铺满，不再套 16:9 AspectRatio 和圆角。
            PlayerStage(controller: widget.controller, fullscreen: true),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      GlassCircleButton(
                        icon: Icons.arrow_back_rounded,
                        size: 36,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      GlassCircleButton(
                        icon: Icons.tune_rounded,
                        size: 36,
                        onTap: () =>
                            setState(() => _showSettings = !_showSettings),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PlayerControls(
                        controller: widget.controller,
                        onQualityHint: _showQualityHint,
                      ),
                      if (_showSettings) ...<Widget>[
                        const SizedBox(height: 8),
                        PlayerDanmakuSettings(controller: widget.controller),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
