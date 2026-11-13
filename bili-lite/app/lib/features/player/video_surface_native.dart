import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'danmaku_layout.dart';
import 'video_surface.dart';

/// 原生端播放表面：基于 `video_player` 插件。
///
/// 播放器渲染成一个 Texture，因此弹幕层可以直接用 Flutter 画布盖在上面。
///
/// 桌面端（Windows / macOS / Linux）目前没有可用的 video_player 实现，
/// 插件调用会抛 MissingPluginException，这里捕获后转成一条明确的错误提示，
/// 由上层降级到「用系统播放器打开」。
VideoSurface createVideoSurface({
  required void Function(Duration position) onPosition,
  required void Function(Duration duration) onDuration,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String? error) onError,
}) =>
    _NativeVideoSurface(
      onPosition: onPosition,
      onDuration: onDuration,
      onPlayingChanged: onPlayingChanged,
      onError: onError,
    );

class _NativeVideoSurface implements VideoSurface {
  _NativeVideoSurface({
    required this.onPosition,
    required this.onDuration,
    required this.onPlayingChanged,
    required this.onError,
  });

  final void Function(Duration position) onPosition;
  final void Function(Duration duration) onDuration;
  final void Function(bool isPlaying) onPlayingChanged;
  final void Function(String? error) onError;

  VideoPlayerController? _controller;
  bool _disposed = false;

  @override
  Widget get widget {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  String? get error => _error;
  String? _error;

  @override
  Future<void> open(String url, {Map<String, String> headers = const <String, String>{}}) async {
    _error = null;
    onError(null);
    try {
      final controller = VideoPlayerController.network(
        url,
        httpHeaders: headers,
      );
      _controller = controller;
      controller.addListener(_onChanged);
      await controller.initialize();
      if (_disposed) {
        controller.removeListener(_onChanged);
        await controller.dispose();
        return;
      }
      onDuration(controller.value.duration);
      // 加载完就自动起播，与 Web 端行为一致。
      await controller.play();
    } catch (e) {
      _error = _describe(e);
      onError(_error);
    }
  }

  void _onChanged() {
    final c = _controller;
    if (c == null || _disposed) return;
    onPosition(c.value.position);
    onPlayingChanged(c.value.isPlaying);
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.play();
  }

  @override
  Future<void> pause() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(position);
    onPosition(position);
  }

  @override
  void setDanmaku(DanmakuSource? source) {
    // 原生端的弹幕画在 Flutter 画布上（Texture 之上），不需要交给底层。
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onChanged);
      c.dispose();
    }
  }

  /// 把插件抛出的异常翻译成用户看得懂的话。
  static String _describe(Object e) {
    final text = e.toString();
    if (text.contains('MissingPluginException') ||
        text.contains('No implementation found')) {
      return '当前平台暂不支持内置播放器（Windows / macOS / Linux 暂缺视频插件实现），'
          '可改用系统播放器打开';
    }
    return '播放失败：$text';
  }
}

/// 供上层判断当前平台是否真的有可用播放器实现。
bool get nativePlayerSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
