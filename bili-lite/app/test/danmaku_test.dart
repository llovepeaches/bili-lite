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
      // 字号 20 → 视觉字号 10，两个字宽 20，居中后 x = 490
      expect(a.first.x, 490);
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
      expect(sprites.first.fontSize, 20);
    });
  });

  group('弹幕颜色', () {
    test('十进制颜色转 CSS', () {
      expect(danmakuColorToCss(0xFFFFFF, 1), 'rgba(255, 255, 255, 1.0)');
      expect(danmakuColorToCss(0x000000, 0.5), 'rgba(0, 0, 0, 0.5)');
    });
  });
}
