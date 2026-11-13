import '../../data/models.dart';

/// 一条弹幕在时间轴上的落位结果。
class DanmakuPlacement {
  const DanmakuPlacement({
    required this.danmaku,
    required this.lane,
    required this.startMs,
    required this.endMs,
  });

  final Danmaku danmaku;

  /// 轨道序号（0 是最上面一条）。滚动与固定弹幕各自有独立的轨道池。
  final int lane;

  /// 出现与消失时刻（毫秒，相对视频起点）。
  final int startMs;
  final int endMs;

  bool get isFixed => danmaku.mode == 4 || danmaku.mode == 5;
}

/// 弹幕时间轴：负责把一堆弹幕分配到互不重叠的轨道上。
///
/// 为什么要有「轨道」：B 站弹幕是 1980 年代的弹幕系统，同一时刻的滚动弹幕
/// 会从右向左穿过整屏。如果不做轨道分配，两条长度相近的弹幕会叠在同一行，
/// 互相「盖脸」——这正是原版客户端用轨道表解决的老问题。
///
/// 算法（与原版思路一致）：
///   * 滚动弹幕（mode 1）：维护每条轨道的「空闲时刻」，一条弹幕可以放进
///     空闲时刻 ≤ 自己出现时刻的轨道；找不到就新开一条轨道。
///   * 顶部（mode 5）/ 底部（mode 4）固定弹幕：各自独立轨道池，占用期间
///     同轨道不可再放。
///
/// 这份逻辑是纯 Dart，不依赖 Flutter，因此 Web 端（用 DOM canvas 绘制）
/// 与原生端（用 Flutter 画布绘制）共用同一份时间轴，不会出现两端不一致。
class DanmakuTimeline {
  DanmakuTimeline(List<Danmaku> items) {
    final sorted = List<Danmaku>.of(items)
      ..sort((a, b) => a.time.compareTo(b.time));
    _items = sorted;
    _build();
  }

  /// 滚动弹幕在屏幕上停留的时长（毫秒）。
  static const int scrollDurationMs = 8000;

  /// 固定弹幕（顶部/底部）的停留时长（毫秒）。
  static const int fixedDurationMs = 4000;

  late final List<Danmaku> _items;

  /// 与 [_items] 等长的落位表；无法落位的（超长视频末尾等）为 null。
  final List<DanmakuPlacement?> _placements = <DanmakuPlacement?>[];

  /// 滚动轨道数（渲染时用它算行高）。
  int scrollLanes = 0;

  /// 顶部固定轨道数。
  int topLanes = 0;

  /// 底部固定轨道数。
  int bottomLanes = 0;

  /// 全部弹幕（按时间排序）。
  List<Danmaku> get items => _items;

  void _build() {
    final List<int> scrollFreeAt = <int>[];
    final List<int> topFreeAt = <int>[];
    final List<int> bottomFreeAt = <int>[];

    for (final d in _items) {
      final int start = d.time;
      if (d.mode == 4) {
        final lane = _takeLane(bottomFreeAt, start, fixedDurationMs);
        bottomFreeAt[lane] = start + fixedDurationMs;
        _placements.add(DanmakuPlacement(
          danmaku: d,
          lane: lane,
          startMs: start,
          endMs: start + fixedDurationMs,
        ));
      } else if (d.mode == 5) {
        final lane = _takeLane(topFreeAt, start, fixedDurationMs);
        topFreeAt[lane] = start + fixedDurationMs;
        _placements.add(DanmakuPlacement(
          danmaku: d,
          lane: lane,
          startMs: start,
          endMs: start + fixedDurationMs,
        ));
      } else {
        final lane = _takeLane(scrollFreeAt, start, scrollDurationMs);
        scrollFreeAt[lane] = start + scrollDurationMs;
        _placements.add(DanmakuPlacement(
          danmaku: d,
          lane: lane,
          startMs: start,
          endMs: start + scrollDurationMs,
        ));
      }
    }

    scrollLanes = scrollFreeAt.length;
    topLanes = topFreeAt.length;
    bottomLanes = bottomFreeAt.length;
  }

  /// 在轨道池里找一条「空闲时刻 ≤ start」的轨道；找不到就新开一条。
  static int _takeLane(List<int> freeAt, int start, int duration) {
    for (int i = 0; i < freeAt.length; i++) {
      if (freeAt[i] <= start) {
        freeAt[i] = start + duration;
        return i;
      }
    }
    freeAt.add(start + duration);
    return freeAt.length - 1;
  }

  /// 取某一时刻屏幕上应该显示的弹幕。
  ///
  /// [positionMs] 是当前播放进度（毫秒）。
  List<DanmakuPlacement> activeAt(int positionMs) {
    final out = <DanmakuPlacement>[];
    for (int i = 0; i < _items.length; i++) {
      final p = _placements[i];
      if (p == null) continue;
      if (positionMs < p.startMs) break; // 已排序，后面只会更晚
      if (positionMs < p.endMs) out.add(p);
    }
    return out;
  }
}
