import 'package:flutter/material.dart';

import 'danmaku_layout.dart';

/// 原生端弹幕覆盖层：把弹幕画在视频 Texture 之上。
///
/// Web 端不用这个组件——那里的视频是真实 DOM 元素，永远盖在 Flutter 画布
/// 之上，弹幕必须画在同一层 DOM 里（见 video_surface_web.dart）。
/// 排版公式两边共用 [DanmakuLayout]。
class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    Key? key,
    required this.source,
    required this.position,
    this.enabled = true,
  }) : super(key: key);

  /// 弹幕数据源；null 表示没有弹幕。
  final DanmakuSource? source;

  /// 当前播放进度。
  final Duration position;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = source;
    if (!enabled || s == null || s.isEmpty) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _DanmakuPainter(source: s, position: position),
        size: Size.infinite,
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({required this.source, required this.position});

  final DanmakuSource source;
  final Duration position;

  @override
  void paint(Canvas canvas, Size size) {
    final sprites = DanmakuLayout.sprites(
      source: source,
      position: position,
      size: size,
      measure: _measure,
    );
    for (final sprite in sprites) {
      final painter = TextPainter(
        text: TextSpan(
          text: sprite.text,
          style: TextStyle(
            color: Color(sprite.color | 0xFF000000),
            fontSize: sprite.fontSize,
            height: 1.0,
            shadows: const <Shadow>[
              Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      // 整体不透明度通过颜色 alpha 叠加。
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Color.fromARGB(
            (source.opacity.clamp(0.0, 1.0) * 255).round(), 255, 255, 255),
      );
      painter.paint(canvas, Offset(sprite.x, sprite.y));
      canvas.restore();
    }
  }

  /// 用 TextPainter 量文字宽度，并缓存结果（同一段文字宽度是固定的）。
  static final Map<String, double> _widthCache = <String, double>{};

  double _measure(String text, double fontSize) {
    final key = '$fontSize|$text';
    final cached = _widthCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    _widthCache[key] = width;
    return width;
  }

  @override
  bool shouldRepaint(_DanmakuPainter old) {
    return old.position != position ||
        old.source != source ||
        old.source.opacity != source.opacity ||
        old.source.fontScale != source.fontScale;
  }
}
