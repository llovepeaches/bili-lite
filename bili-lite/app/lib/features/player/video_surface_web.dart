// Web 端播放表面需要直接操作 DOM（<video> + 弹幕 <canvas>），
// 这里确实要用到 dart:html，属于有意为之。
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'danmaku_layout.dart';
import 'video_surface.dart';

/// Web 端播放表面：自建 DOM 播放器（`<video>` + 弹幕 `<canvas>`）。
///
/// 为什么不用 `video_player_web`：
///   它把画面交给 `HtmlElementView`，也就是一个真实的 DOM 元素。浏览器的
///   合成顺序决定这个元素永远盖在 Flutter 画布之上——弹幕层如果画在
///   Flutter 里，会被视频挡得一点都看不见。
///   所以 Web 端改成把 `<video>` 与弹幕 `<canvas>` 放进同一个容器 div，
///   两者都是 DOM 元素，canvas 在后 naturally 盖在 video 上；
///   弹幕的排版公式与原生端共用 [DanmakuLayout]，两端观感一致。
///
/// 播放地址必须走 BFF 的 `/api/stream`：
///   B 站 CDN 有 referer 防盗链，浏览器端 `<video src>` 无法自带 Referer，
///   直连必然 403；同源代理还顺带解决了 CORS。
VideoSurface createVideoSurface({
  required void Function(Duration position) onPosition,
  required void Function(Duration duration) onDuration,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String? error) onError,
}) =>
    _WebVideoSurface(
      onPosition: onPosition,
      onDuration: onDuration,
      onPlayingChanged: onPlayingChanged,
      onError: onError,
    );

class _WebVideoSurface implements VideoSurface {
  _WebVideoSurface({
    required this.onPosition,
    required this.onDuration,
    required this.onPlayingChanged,
    required this.onError,
  });

  final void Function(Duration position) onPosition;
  final void Function(Duration duration) onDuration;
  final void Function(bool isPlaying) onPlayingChanged;
  final void Function(String? error) onError;

  static int _seq = 0;

  html.DivElement? _container;
  html.VideoElement? _video;
  html.CanvasElement? _canvas;
  html.CanvasRenderingContext2D? _ctx;

  DanmakuSource? _danmaku;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _disposed = false;
  String? _error;

  @override
  Widget get widget {
    final container = _container;
    if (container == null) {
      return const ColoredBox(color: Colors.black);
    }
    final viewType = 'bili-player-${_seq++}';
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      return container;
    });
    return HtmlElementView(viewType: viewType);
  }

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get isReady => _video != null;

  @override
  bool get isPlaying => _playing;

  @override
  String? get error => _error;

  @override
  Future<void> open(String url, {Map<String, String> headers = const <String, String>{}}) async {
    _error = null;
    onError(null);

    final container = html.DivElement()
      ..style.position = 'relative'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000000'
      ..style.overflow = 'hidden';

    final video = html.VideoElement()
      ..src = url
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = '#000000'
      // 不显示浏览器原生控制条：控制条统一由 Flutter 画，六端观感一致，
      // 也避免原生控制条和弹幕 canvas 抢层级。
      ..controls = false
      ..preload = 'auto'
      ..crossOrigin = 'anonymous';

    final canvas = html.CanvasElement()
      ..style.position = 'absolute'
      ..style.left = '0'
      ..style.top = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.pointerEvents = 'none';

    container.children.add(video);
    container.children.add(canvas);

    _container = container;
    _video = video;
    _canvas = canvas;
    _ctx = canvas.context2D;

    video.onLoadedMetadata.listen((html.Event _) {
      final seconds = video.duration;
      if (seconds.isFinite && seconds > 0) {
        _duration = Duration(milliseconds: (seconds * 1000).round());
        onDuration(_duration);
      }
    });
    video.onTimeUpdate.listen((html.Event _) {
      final seconds = video.currentTime;
      if (seconds.isFinite) {
        _position = Duration(milliseconds: (seconds * 1000).round());
        onPosition(_position);
      }
    });
    video.onPlay.listen((html.Event _) {
      _playing = true;
      onPlayingChanged(true);
      _startLoop();
    });
    video.onPause.listen((html.Event _) {
      _playing = false;
      onPlayingChanged(false);
    });
    video.onError.listen((html.Event _) {
      _error = '视频加载失败：可能是上游防盗链或网络不通，可改用官方播放器';
      onError(_error);
    });

    _startLoop();
    // 自动起播：原生端也是加载完就播，两端行为一致。
    unawaited(play());
  }

  /// 弹幕绘制循环。用 requestAnimationFrame 保证与浏览器刷新同步。
  void _startLoop() {
    if (_disposed) return;
    html.window.requestAnimationFrame(_tick);
  }

  void _tick(num _) {
    if (_disposed) return;
    _drawDanmaku();
    html.window.requestAnimationFrame(_tick);
  }

  void _drawDanmaku() {
    final canvas = _canvas;
    final ctx = _ctx;
    final video = _video;
    final source = _danmaku;
    if (canvas == null || ctx == null || video == null) return;

    final rect = canvas.getBoundingClientRect();
    final double width = rect.width.toDouble();
    final double height = rect.height.toDouble();
    if (width <= 0 || height <= 0) return;

    final dpr = html.window.devicePixelRatio.toDouble();
    final pixelW = (width * dpr).round();
    final pixelH = (height * dpr).round();
    if (canvas.width != pixelW || canvas.height != pixelH) {
      canvas.width = pixelW;
      canvas.height = pixelH;
    }
    ctx.setTransform(dpr.toDouble(), 0, 0, dpr.toDouble(), 0, 0);
    ctx.clearRect(0, 0, width, height);

    if (source == null || source.isEmpty) return;

    final sprites = DanmakuLayout.sprites(
      source: source,
      position: _position,
      size: Size(width, height),
      measure: (String text, double fontSize) {
        ctx.font = '${fontSize.toStringAsFixed(1)}px sans-serif';
        return (ctx.measureText(text).width ?? 0).toDouble();
      },
    );
    for (final s in sprites) {
      ctx.font = '${s.fontSize.toStringAsFixed(1)}px sans-serif';
      ctx.fillStyle = danmakuColorToCss(s.color, source.opacity);
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.6)';
      ctx.lineWidth = 2;
      ctx.strokeText(s.text, s.x, s.y + s.fontSize);
      ctx.fillText(s.text, s.x, s.y + s.fontSize);
    }
  }

  @override
  Future<void> play() async {
    final v = _video;
    if (v == null) return;
    try {
      await v.play();
    } catch (_) {
      // 浏览器会拦截没有用户手势的自动播放，忽略即可。
    }
  }

  @override
  Future<void> pause() async {
    _video?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final v = _video;
    if (v == null) return;
    v.currentTime = position.inMilliseconds / 1000.0;
    _position = position;
    onPosition(position);
  }

  @override
  void setDanmaku(DanmakuSource? source) {
    _danmaku = source;
  }

  @override
  void dispose() {
    _disposed = true;
    _video?.pause();
    _video?.src = '';
    _video = null;
    _canvas = null;
    _ctx = null;
    _container = null;
  }
}
