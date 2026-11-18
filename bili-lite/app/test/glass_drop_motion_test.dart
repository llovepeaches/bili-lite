import 'package:bililite/widgets/glass_drop_motion.dart';
import 'package:flutter_test/flutter_test.dart';

/// 水滴透镜运动模型的**行为**回归测试。
///
/// 截图只能证明「看起来对」，这些断言证明「算得对」——
/// 比如「第二次切换时水滴必须真的动」（第一版就是漏了这一点，
/// 弹簧从 1 跳 1，水滴纹丝不动）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 三个 tab，中心分别在 50 / 150 / 250。
  GlassDropMotion build() {
    final GlassDropMotion m = GlassDropMotion(vsync: TestVSync());
    m.setCenters(<double>[50, 150, 250]);
    return m;
  }

  group('GlassDropMotion 飞行', () {
    test('静止态落在选中的 tab 上', () {
      final GlassDropMotion m = build();
      m.jumpTo(1);
      expect(m.x, 150);
      expect(m.index, 1);
      expect(m.stretch, 1.0, reason: '静止时不该有形变');
    });

    test('切到第二个 tab 后，水滴真的移动了', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      final double before = m.x;

      m.travelTo(1);
      // 飞行刚起步：进度从 0 开始，水滴还在原处附近。
      expect(m.travel, lessThan(0.5), reason: '飞行进度应从小到大推进');

      // 关键回归点：**第二次**切换也必须动。
      // 第一版把弹簧起点写成了 `_travel.value`（上一次结束后是 1），
      // 于是弹簧变成 1 → 1，水滴根本不会动。
      m.travelTo(2);
      expect(m.travel, lessThan(1.0), reason: '第二次飞行必须重新从 0 起步');
      expect(m.x, isNot(equals(before)));
    });

    test('飞行途中会拉伸，静止后恢复', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      m.travelTo(2);

      // 手工把进度推到飞行中段。
      m.setTravelForTest(0.5);
      expect(m.stretch, greaterThan(1.0), reason: '飞行中段应当被拉长');

      m.setTravelForTest(0.0);
      expect(m.stretch, 1.0, reason: '起点不该拉伸');

      m.setTravelForTest(1.0);
      expect(m.stretch, 1.0, reason: '落位后不该拉伸');
    });

    test('拉伸幅度随距离增大', () {
      final GlassDropMotion m = build();
      m.setCenters(<double>[50, 150, 250]);
      m.jumpTo(0);
      m.travelTo(1);
      m.setTravelForTest(0.5);
      final double near = m.stretch;

      final GlassDropMotion far = build();
      far.jumpTo(0);
      far.travelTo(2);
      far.setTravelForTest(0.5);
      final double distant = far.stretch;

      expect(distant, greaterThan(near), reason: '飞得越远拉得越开');
    });
  });

  group('GlassDropMotion 擦洗', () {
    test('水滴跟手移动', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      m.scrubTo(180);
      expect(m.x, 180);
      expect(m.scrubbing, isTrue);
    });

    test('拖出底栏时被钳制在最后一个 tab', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      m.scrubTo(9999);
      expect(m.x, 250, reason: '水滴不能被拖出底栏');

      m.scrubTo(-9999);
      expect(m.x, 50, reason: '水滴不能被拖出底栏');
    });

    test('松手落到最近的 tab', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      m.scrubTo(180);
      m.scrubRelease();
      expect(m.index, 1, reason: '180 更靠近第二个 tab（150）');
      expect(m.x, closeTo(180, 0.01), reason: '松手瞬间应停在手指位置，不能瞬移');
    });

    test('松手后从手指位置继续飞到落点', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      m.scrubTo(230);
      m.scrubRelease();
      expect(m.index, 2);

      // 落位之后，水滴应当正好在第三个 tab 的中心。
      m.setTravelForTest(1.0);
      expect(m.x, 250);
    });
  });

  group('GlassDropMotion 抬起', () {
    test('抬起时玻璃下的内容被放大', () {
      final GlassDropMotion m = build();
      m.jumpTo(0);
      expect(m.underGlassScale, closeTo(1.0, 0.001));

      m.setLiftForTest(1.0);
      expect(m.underGlassScale, greaterThan(1.1), reason: '玻璃下的图标应当被折射放大');
    });
  });
}
