import 'dart:ui' show Size;

import '../../data/models.dart';
import 'danmaku_timeline.dart';

/// 一条已经算好位置的弹幕，交给具体渲染器（Flutter 画布 / DOM canvas）画。
class DanmakuSprite {
  const DanmakuSprite({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.x,
    required this.y,
    required this.isFixed,
  });

  final String text;

  /// ARGB 颜色。
  final int color;

  final double fontSize;

  /// 左上角坐标（x 是文字左边缘）。
  final double x;
  final double y;

  /// 固定弹幕（顶部/底部）不横向移动。
  final bool isFixed;
}

/// 弹幕数据源：时间轴 + 显示参数。
///
/// 原生端与 Web 端各自渲染，但共用同一份时间轴与排版公式，
/// 保证同一视频在手机和浏览器上看到的弹幕一致。
class DanmakuSource {
  DanmakuSource({required this.timeline, this.opacity = 1.0, this.fontScale = 1.0});

  final DanmakuTimeline timeline;

  /// 整体不透明度（0 ~ 1）。
  double opacity;

  /// 字号缩放。
  double fontScale;

  bool get isEmpty => timeline.items.isEmpty;
}

/// 弹幕排版：把「当前时刻该出现的弹幕」换算成屏幕上的坐标。
///
/// 文字宽度由调用方通过 [measure] 提供——两端测量方式不同
/// （原生用 TextPainter，Web 用 canvas.measureText），但排版公式相同。
class DanmakuLayout {
  const DanmakuLayout._();

  /// 行高（像素）。
  static const double lineHeight = 26;

  /// 计算某一时刻的弹幕精灵列表。
  ///
  /// [measure] 用来量文字宽度，签名是 `(text, fontSize) -> width`。
  static List<DanmakuSprite> sprites({
    required DanmakuSource source,
    required Duration position,
    required Size size,
    required double Function(String text, double fontSize) measure,
  }) {
    final int posMs = position.inMilliseconds;
    final active = source.timeline.activeAt(posMs);
    final out = <DanmakuSprite>[];

    for (final p in active) {
      final d = p.danmaku;
      if (d.text.isEmpty) continue;
      final double baseFont = d.size <= 0 ? 25 : d.size.toDouble();
      final double fontSize = (baseFont * 0.5) * source.fontScale;
      final double textWidth = measure(d.text, fontSize);
      final bool fixed = p.isFixed;

      if (fixed) {
        final bool isTop = d.mode == 5;
        final double y = isTop
            ? p.lane * lineHeight + 2
            : size.height - (p.lane + 1) * lineHeight - 2;
        out.add(DanmakuSprite(
          text: d.text,
          color: d.color,
          fontSize: fontSize,
          x: (size.width - textWidth) / 2,
          y: y,
          isFixed: true,
        ));
        continue;
      }

      // 滚动弹幕：从右侧进入，穿过整屏后从左侧离开。
      final double elapsed = (posMs - p.startMs) / 1000.0;
      final double total = DanmakuTimeline.scrollDurationMs / 1000.0;
      final double travel = size.width + textWidth;
      final double x = size.width - (elapsed / total) * travel;
      final double y = p.lane * lineHeight + 2;
      out.add(DanmakuSprite(
        text: d.text,
        color: d.color,
        fontSize: fontSize,
        x: x,
        y: y,
        isFixed: false,
      ));
    }
    return out;
  }
}

/// 把 B 站的十进制颜色（0xRRGGBB）转成 CSS 颜色串。
String danmakuColorToCss(int color, double opacity) {
  final int rgb = color & 0xFFFFFF;
  final int r = (rgb >> 16) & 0xFF;
  final int g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  return 'rgba($r, $g, $b, ${opacity.clamp(0.0, 1.0)})';
}

/// 供测试与工具复用的简单实现：从模型列表构造时间轴。
DanmakuTimeline buildTimeline(List<Danmaku> items) => DanmakuTimeline(items);
