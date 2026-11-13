import 'package:flutter/material.dart';

import 'danmaku_layout.dart';
import 'video_surface_native.dart'
    if (dart.library.html) 'video_surface_web.dart' as impl;

/// 播放表面：把「视频画面」这一层抽象出来，让上层不关心平台差异。
///
/// 为什么要抽象：
///   * 原生端（Android / iOS）用 `video_player` 插件，播放器是一个 Texture，
///     Flutter 可以在上面盖任何东西（弹幕层、控制条）。
///   * Web 端 `video_player_web` 的实现是 `HtmlElementView`——一个真实的
///     DOM 元素。浏览器的合成顺序决定它永远盖在 Flutter 画布之上，
///     所以弹幕层画在 Flutter 里会被视频挡住。
///     因此 Web 端改成自建 DOM 播放器：<video> 与 <canvas> 放在同一个容器里，
///     弹幕直接画在 canvas 上，位置计算与原生端共用 [DanmakuLayout]。
///   * 桌面端（Windows / macOS / Linux）当前没有可用的播放器实现，
///     降级为「用系统播放器打开」提示。
abstract class VideoSurface {
  /// 播放画面。
  Widget get widget;

  /// 当前播放位置。
  Duration get position;

  /// 视频总时长。
  Duration get duration;

  /// 是否已就绪（可以播放）。
  bool get isReady;

  /// 是否正在播放。
  bool get isPlaying;

  /// 错误信息（null 表示没有错误）。
  String? get error;

  /// 准备播放地址。
  Future<void> open(String url, {Map<String, String> headers});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 主动释放底层资源。
  void dispose();

  /// 把弹幕数据交给播放表面。
  ///
  /// 原生端这个方法是空实现：弹幕由 Flutter 画布绘制在 Texture 之上
  /// （见 danmaku_overlay.dart），根本不需要交给底层。
  /// Web 端必须由底层处理：视频是真实 DOM 元素，永远盖在 Flutter 画布之上，
  /// 弹幕只能画在同一层 DOM 的 canvas 里。
  void setDanmaku(DanmakuSource? source) {}
}

/// 创建一个当前平台的播放表面。
VideoSurface createVideoSurface({
  required void Function(Duration position) onPosition,
  required void Function(Duration duration) onDuration,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String? error) onError,
}) =>
    impl.createVideoSurface(
      onPosition: onPosition,
      onDuration: onDuration,
      onPlayingChanged: onPlayingChanged,
      onError: onError,
    );
