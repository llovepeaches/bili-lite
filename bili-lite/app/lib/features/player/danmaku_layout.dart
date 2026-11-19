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

/// 弹幕显示区域：按画面高度的比例，从顶部开始限制弹幕可见范围。
///
/// 用枚举而不是自由比例，是为了让原生画布与 Web canvas 只有
/// [danmakuAreaRatio] 这一个换算入口，两端不会算得不一样，也便于纯 Dart 单测。
/// 档位与常见客户端一致（全屏 / 3/4 / 半屏 / 1/4），主要用途是让弹幕
/// 不挡住画面下半部分的字幕与人物。
enum DanmakuArea { full, threeQuarters, half, quarter }

const Map<DanmakuArea, double> _danmakuAreaRatios = <DanmakuArea, double>{
  DanmakuArea.full: 1.0,
  DanmakuArea.threeQuarters: 0.75,
  DanmakuArea.half: 0.5,
  DanmakuArea.quarter: 0.25,
};

/// 各档位占据画面高度的比例。
double danmakuAreaRatio(DanmakuArea area) => _danmakuAreaRatios[area] ?? 1.0;

/// 设置面板按顺序展示的档位标签，与 [DanmakuArea] 的声明顺序一一对应。
const List<String> danmakuAreaLabels = <String>['全屏', '3/4', '半屏', '1/4'];

/// 枚举转分段控件下标。
int danmakuAreaIndex(DanmakuArea area) => DanmakuArea.values.indexOf(area);

/// 分段控件下标转枚举；越界（含脏的持久化值）一律回落全屏，
/// 避免一个坏数据把弹幕整片藏起来。
DanmakuArea danmakuAreaFromIndex(int index) {
  if (index < 0 || index >= DanmakuArea.values.length) return DanmakuArea.full;
  return DanmakuArea.values[index];
}

/// 弹幕数据源：时间轴 + 显示参数。
///
/// 原生端与 Web 端各自渲染，但共用同一份时间轴与排版公式，
/// 保证同一视频在手机和浏览器上看到的弹幕一致。
class DanmakuSource {
  DanmakuSource({
    required this.timeline,
    this.opacity = 1.0,
    this.fontScale = 1.0,
    this.area = DanmakuArea.full,
  });

  final DanmakuTimeline timeline;

  /// 整体不透明度（0 ~ 1）。
  double opacity;

  /// 字号缩放。
  double fontScale;

  /// 可见区域；原生画布与 Web canvas 都从 [DanmakuLayout.sprites] 读取，
  /// 不需要各自实现一遍裁剪。
  DanmakuArea area;

  bool get isEmpty => timeline.items.isEmpty;
}

/// 弹幕字体回退栈（原生 TextPainter 用）。
///
/// 不指定字体时，部分 Android / 桌面环境会落到不含中文字形的默认字体，
/// 弹幕显示成方块。这里按「中文优先、无衬线兜底」的顺序声明，
/// 原生端与 Web 端共用同一份顺序，保证两端观感一致。
const List<String> danmakuFontFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'sans-serif',
];

/// 与 [danmakuFontFallback] 等价的 CSS 字体串（Web canvas ctx.font 用）。
const String danmakuFontCss =
    '"PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", '
    '"Noto Sans CJK SC", sans-serif';

/// 把 B 站弹幕原始字号换算成屏幕像素字号。
///
/// 原实现固定乘 0.5：标准 size=25 只剩 12.5px，在手机上偏小、
/// 在大字号档又会挤占整行。这里改为 0.8 倍并夹到 [11, 24]，
/// 既保证标准档清晰可读，又避免极端字号把画面盖满或溢出轨道。
double danmakuFontSize(int rawSize, double fontScale) {
  final double base = rawSize <= 0 ? 25 : rawSize.toDouble();
  return (base * 0.8 * fontScale).clamp(11.0, 24.0).toDouble();
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

    // 显示区域只作用于竖直方向：弹幕统一排布在画面顶部 [0, areaHeight] 内。
    // 轨道数按可用高度重新收敛，越界轨道取模回卷到区域内——缩小区域只会
    // 让弹幕更密集地复用轨道，而不是整条消失。
    // floor(areaHeight / lineHeight) 还保证最下面一条不会越界：
    // (laneCount-1)*26 + 2 + 最大字号 24 = laneCount*26 ≤ areaHeight。
    final double fullHeight = size.height > 0 ? size.height : 0.0;
    final double areaHeight = fullHeight * danmakuAreaRatio(source.area);
    final int rawLanes = (areaHeight / lineHeight).floor();
    final int laneCount = rawLanes < 1 ? 1 : rawLanes;

    for (final p in active) {
      final d = p.danmaku;
      if (d.text.isEmpty) continue;
      final double fontSize = danmakuFontSize(d.size, source.fontScale);
      final double textWidth = measure(d.text, fontSize);
      final bool fixed = p.isFixed;
      final int lane = p.lane % laneCount;

      if (fixed) {
        final bool isTop = d.mode == 5;
        final double y = isTop
            ? lane * lineHeight + 2
            : areaHeight - (lane + 1) * lineHeight - 2;
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
      final double y = lane * lineHeight + 2;
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
