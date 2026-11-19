import 'dart:ui' show Size;

import 'package:bililite/data/models.dart';
import 'package:bililite/features/player/danmaku_layout.dart';
import 'package:bililite/features/player/danmaku_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('弹幕时间轴', () {
    test('同一时刻的滚动弹幕分配到不同轨道', () {
      final timeline = DanmakuTimeline(<Danmaku>[
        const Danmaku(time: 0, mode: 1, text: 'A'),
        const Danmaku(time: 100, mode: 1, text: 'B'),
        const Danmaku(time: 200, mode: 1, text: 'C'),
      ]);
      final active = timeline.activeAt(300);
      expect(active.length, 3);
      // 三条同时在屏，必须落在三条不同轨道上，否则会互相盖脸。
      final lanes = active.map((a) => a.lane).toSet();
      expect(lanes.length, 3);
    });

    test('超出停留时长的弹幕不再显示', () {
      final timeline = DanmakuTimeline(<Danmaku>[
        const Danmaku(time: 0, mode: 1, text: 'A'),
      ]);
      expect(timeline.activeAt(100).length, 1);
      expect(timeline.activeAt(DanmakuTimeline.scrollDurationMs + 1).length, 0);
    });

    test('顶部与底部固定弹幕各用独立轨道池', () {
      final timeline = DanmakuTimeline(<Danmaku>[
        const Danmaku(time: 0, mode: 5, text: '顶'),
        const Danmaku(time: 0, mode: 4, text: '底'),
      ]);
      final active = timeline.activeAt(100);
      expect(active.length, 2);
      expect(active[0].lane, 0);
      expect(active[1].lane, 0);
      expect(active[0].isFixed, isTrue);
      expect(active[1].isFixed, isTrue);
    });

    test('按时间排序后 activeAt 可以提前 break', () {
      final timeline = DanmakuTimeline(<Danmaku>[
        const Danmaku(time: 5000, mode: 1, text: '晚'),
        const Danmaku(time: 0, mode: 1, text: '早'),
      ]);
      expect(timeline.items.first.text, '早');
    });
  });

  group('弹幕排版', () {
    double measure(String text, double fontSize) => text.length * fontSize;

    test('滚动弹幕从右侧进入并向左移动', () {
      final source = DanmakuSource(
        timeline: DanmakuTimeline(<Danmaku>[
          const Danmaku(time: 0, mode: 1, text: 'AB', size: 20),
        ]),
      );
      final start = DanmakuLayout.sprites(
        source: source,
        position: Duration.zero,
        size: const Size(1000, 400),
        measure: measure,
      );
      final later = DanmakuLayout.sprites(
        source: source,
        position: const Duration(seconds: 4),
        size: const Size(1000, 400),
        measure: measure,
      );
      expect(start.first.x, greaterThan(later.first.x));
      expect(start.first.x, greaterThan(900));
      expect(later.first.x, lessThan(1000));
    });

    test('固定弹幕水平居中且不随时间移动', () {
      final source = DanmakuSource(
        timeline: DanmakuTimeline(<Danmaku>[
          const Danmaku(time: 0, mode: 5, text: 'AB', size: 20),
        ]),
      );
      final a = DanmakuLayout.sprites(
        source: source,
        position: Duration.zero,
        size: const Size(1000, 400),
        measure: measure,
      );
      final b = DanmakuLayout.sprites(
        source: source,
        position: const Duration(seconds: 2),
        size: const Size(1000, 400),
        measure: measure,
      );
      expect(a.first.x, b.first.x);
      // 字号 20 → 视觉字号 16，两个字宽 32，居中后 x = 484
      expect(a.first.x, 484);
      expect(a.first.isFixed, isTrue);
    });

    test('底部固定弹幕贴底', () {
      final source = DanmakuSource(
        timeline: DanmakuTimeline(<Danmaku>[
          const Danmaku(time: 0, mode: 4, text: 'X', size: 20),
        ]),
      );
      final sprites = DanmakuLayout.sprites(
        source: source,
        position: Duration.zero,
        size: const Size(1000, 400),
        measure: measure,
      );
      expect(sprites.first.y, 400 - 26 - 2);
    });

    test('字号缩放会同时影响文字尺寸与宽度', () {
      final source = DanmakuSource(
        timeline: DanmakuTimeline(<Danmaku>[
          const Danmaku(time: 0, mode: 1, text: 'AB', size: 20),
        ]),
        fontScale: 2.0,
      );
      final sprites = DanmakuLayout.sprites(
        source: source,
        position: Duration.zero,
        size: const Size(1000, 400),
        measure: measure,
      );
      // size 20 × 0.8 = 16，×2 缩放后 32，但被字号上限夹到 24。
      expect(sprites.first.fontSize, 24);
    });
  });

  group('弹幕字号与字体', () {
    test('标准弹幕字号清晰可读，且被夹在 11~24 内', () {
      // 标准 size=25 → 20px，比旧的 ×0.5（12.5px）更易读。
      expect(danmakuFontSize(25, 1.0), 20);
      // 极小 / 极大字号都有边界，极端值不会把画面盖满或缩成看不见。
      expect(danmakuFontSize(8, 0.6), greaterThanOrEqualTo(11));
      expect(danmakuFontSize(90, 2.0), 24);
      // 非法 size 回落到标准档。
      expect(danmakuFontSize(0, 1.0), 20);
    });

    test('原生与 Web 共用同一份中文字体回退栈', () {
      expect(danmakuFontFallback, contains('PingFang SC'));
      expect(danmakuFontFallback, contains('Microsoft YaHei'));
      expect(danmakuFontFallback, contains('Noto Sans CJK SC'));
      expect(danmakuFontFallback.last, 'sans-serif');
      // CSS 串与回落栈同源，避免两端测量宽度不一致。
      for (final font in danmakuFontFallback) {
        expect(danmakuFontCss, contains(font));
      }
    });
  });

  group('弹幕颜色', () {
    test('十进制颜色转 CSS', () {
      expect(danmakuColorToCss(0xFFFFFF, 1), 'rgba(255, 255, 255, 1.0)');
      expect(danmakuColorToCss(0x000000, 0.5), 'rgba(0, 0, 0, 0.5)');
    });
  });

  group('弹幕显示区域', () {
    double measure(String text, double fontSize) => text.length * fontSize;

    List<DanmakuSprite> render(
      DanmakuArea area,
      List<Danmaku> items, {
      Duration position = Duration.zero,
    }) =>
        DanmakuLayout.sprites(
          source: DanmakuSource(timeline: DanmakuTimeline(items), area: area),
          position: position,
          size: const Size(1000, 400),
          measure: measure,
        );

    test('档位比例、标签与下标互相一致，越界下标回落全屏', () {
      expect(danmakuAreaRatio(DanmakuArea.full), 1.0);
      expect(danmakuAreaRatio(DanmakuArea.threeQuarters), 0.75);
      expect(danmakuAreaRatio(DanmakuArea.half), 0.5);
      expect(danmakuAreaRatio(DanmakuArea.quarter), 0.25);
      expect(danmakuAreaLabels.length, DanmakuArea.values.length);
      for (final area in DanmakuArea.values) {
        expect(danmakuAreaFromIndex(danmakuAreaIndex(area)), area);
      }
      expect(danmakuAreaFromIndex(-1), DanmakuArea.full);
      expect(danmakuAreaFromIndex(99), DanmakuArea.full);
    });

    test('默认全屏时底部固定弹幕仍贴整屏底部', () {
      final sprites = render(DanmakuArea.full, <Danmaku>[
        const Danmaku(time: 0, mode: 4, text: 'X', size: 20),
      ]);
      expect(sprites.first.y, 400 - DanmakuLayout.lineHeight - 2);
    });

    test('半屏区域把底部固定弹幕抬到区域底部', () {
      final sprites = render(DanmakuArea.half, <Danmaku>[
        const Danmaku(time: 0, mode: 4, text: 'X', size: 20),
      ]);
      expect(sprites.first.y, 200 - DanmakuLayout.lineHeight - 2);
    });

    test('所有档位下弹幕都不越出区域，也不会因区域缩小而消失', () {
      final items = <Danmaku>[
        for (int i = 0; i < 20; i++)
          Danmaku(
            time: 0,
            mode: i % 3 == 0 ? 4 : (i % 3 == 1 ? 5 : 1),
            text: '弹幕$i',
            size: 25,
          ),
      ];
      for (final area in DanmakuArea.values) {
        final double limit = 400 * danmakuAreaRatio(area);
        final sprites = render(area, items);
        expect(sprites.length, items.length, reason: '$area 下缩小区域不应让弹幕消失');
        for (final s in sprites) {
          expect(s.y, greaterThanOrEqualTo(-2));
          expect(s.y + s.fontSize, lessThanOrEqualTo(limit + 0.001),
              reason: '$area 下弹幕越出可见区域');
        }
      }
    });

    test('缩小区域后超出轨道数的弹幕回卷到区域内', () {
      // quarter 区域 100px 只有 3 条轨道，第 4 条应回卷到 lane 0。
      final sprites = render(
        DanmakuArea.quarter,
        <Danmaku>[
          const Danmaku(time: 0, mode: 1, text: 'A', size: 20),
          const Danmaku(time: 100, mode: 1, text: 'B', size: 20),
          const Danmaku(time: 200, mode: 1, text: 'C', size: 20),
          const Danmaku(time: 300, mode: 1, text: 'D', size: 20),
        ],
        // 四条错峰入场，要在最后一条出现之后取样才都在屏上。
        position: const Duration(milliseconds: 300),
      );
      expect(sprites.length, 4);
      expect(sprites.map((s) => s.y).toSet().length, 3);
      expect(sprites.last.y, sprites.first.y);
    });
  });
}
