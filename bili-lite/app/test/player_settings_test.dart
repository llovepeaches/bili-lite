import 'package:bililite/data/api_client.dart';
import 'package:bililite/data/models.dart';
import 'package:bililite/data/repository.dart';
import 'package:bililite/features/detail/detail_player.dart';
import 'package:bililite/features/player/danmaku_layout.dart';
import 'package:bililite/features/player/player_controller.dart';
import 'package:bililite/features/player/player_fullscreen.dart';
import 'package:bililite/features/player/player_sections.dart';
import 'package:bililite/widgets/segmented_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阶段 F 回归：横屏全屏播放、弹幕显示大小与显示区域。
///
/// 只构造 PlayerController（不 attachTicker、不跑真实插件），
/// 因此既不会发网络请求，也不会留下 periodic Timer。
class _FakeRepo extends BiliRepository {
  _FakeRepo() : super(client: ApiClient.instance);

  @override
  Future<ApiResponse<PlayUrl>> playUrl(
    String bvid,
    String cid, {
    int qn = 64,
  }) async =>
      ApiResponse<PlayUrl>(data: const PlayUrl(), source: 'test');

  @override
  Future<ApiResponse<DanmakuList>> danmaku(String cid) async =>
      ApiResponse<DanmakuList>(
        data: const DanmakuList(
          list: <Danmaku>[Danmaku(time: 0, mode: 1, text: 'A')],
        ),
        source: 'test',
      );
}

PlayerController _controller([BiliRepository? repo]) => PlayerController(
      bvid: 'BVtest',
      cid: '456',
      repository: repo,
    );

/// 竖向可滚动的容器：给 Column / Row / Expanded 提供有界宽度。
Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

/// 四面有界的容器：全屏 PlayerStage 的 Stack(expand) 需要 tight 约束。
Widget _bounded(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 800, height: 450, child: child),
        ),
      ),
    );

void main() {
  group('弹幕显示参数（控制器）', () {
    test('不透明度与显示大小被夹到合法区间', () {
      final c = _controller();
      addTearDown(c.dispose);

      c.setDanmakuOpacity(-1);
      expect(c.danmakuOpacity, 0.1);
      c.setDanmakuOpacity(2);
      expect(c.danmakuOpacity, 1.0);

      c.setDanmakuFontScale(0.1);
      expect(c.danmakuFontScale, 0.6);
      c.setDanmakuFontScale(9);
      expect(c.danmakuFontScale, 2.0);
      // 显示大小最终由统一公式换算，标准档仍夹在 [11, 24]。
      expect(danmakuFontSize(25, c.danmakuFontScale), 24);
    });

    test('区域按下标设置，越界回落全屏', () {
      final c = _controller();
      addTearDown(c.dispose);

      expect(c.danmakuArea, DanmakuArea.full);
      c.setDanmakuAreaIndex(2);
      expect(c.danmakuArea, DanmakuArea.half);
      c.setDanmakuAreaIndex(99);
      expect(c.danmakuArea, DanmakuArea.full);
    });

    test('异步加载弹幕后仍保留当前显示参数', () async {
      final c = _controller(_FakeRepo());
      addTearDown(c.dispose);

      // 模拟「弹幕还没回来用户就先调了设置」——旧实现会被默认值覆盖。
      c.setDanmakuOpacity(0.5);
      c.setDanmakuFontScale(1.5);
      c.setDanmakuArea(DanmakuArea.quarter);
      await c.load();

      final source = c.danmaku;
      expect(source, isNotNull);
      expect(source!.opacity, 0.5);
      expect(source.fontScale, 1.5);
      expect(source.area, DanmakuArea.quarter);
    });

    test('全屏标志可切换，重复设置不重复通知', () {
      final c = _controller();
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      expect(c.fullscreen, isFalse);
      c.setFullscreen(true);
      c.setFullscreen(true);
      expect(c.fullscreen, isTrue);
      expect(notifications, 1);
      c.setFullscreen(false);
      expect(c.fullscreen, isFalse);
      expect(notifications, 2);
    });
  });

  group('弹幕设置面板', () {
    testWidgets('不透明度 / 显示大小 / 显示区域三个入口都在', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(_harness(PlayerDanmakuSettings(controller: c)));

      expect(find.text('不透明度'), findsOneWidget);
      expect(find.text('显示大小'), findsOneWidget);
      expect(find.text('显示区域'), findsOneWidget);
      expect(find.byType(GlassSegmented), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      // 滑块值改成百分比展示：不透明度 0.9 → 90%，字号 1.0 → 100%。
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('点区域分段控件会写回控制器并同步到数据源', (tester) async {
      final c = _controller(_FakeRepo());
      addTearDown(c.dispose);
      await c.load();
      await tester.pumpWidget(_harness(PlayerDanmakuSettings(controller: c)));

      await tester.tap(find.text('半屏'));
      await tester.pump();

      expect(c.danmakuArea, DanmakuArea.half);
      expect(c.danmaku!.area, DanmakuArea.half);
    });
  });

  group('横屏 / 全屏画面', () {
    testWidgets('内嵌模式保持 16:9，全屏模式铺满且不套 AspectRatio', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);

      await tester.pumpWidget(_bounded(PlayerStage(controller: c)));
      expect(
        find.descendant(
          of: find.byType(PlayerStage),
          matching: find.byType(AspectRatio),
        ),
        findsOneWidget,
      );

      await tester
          .pumpWidget(_bounded(PlayerStage(controller: c, fullscreen: true)));
      expect(
        find.descendant(
          of: find.byType(PlayerStage),
          matching: find.byType(AspectRatio),
        ),
        findsNothing,
      );
      expect(tester.widget<PlayerStage>(find.byType(PlayerStage)).fullscreen,
          isTrue);
    });

    testWidgets('画面右下角全屏按钮可点击并回调', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      var tapped = 0;
      await tester.pumpWidget(_bounded(
        PlayerStage(controller: c, onFullscreen: () => tapped++),
      ));

      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('全屏时内嵌播放器撤下画面，退出后恢复', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await tester.pumpWidget(_harness(DetailPlayer(controller: c)));

      expect(find.byType(PlayerStage), findsOneWidget);
      c.setFullscreen(true);
      await tester.pump();
      expect(find.byType(PlayerStage), findsNothing);
      c.setFullscreen(false);
      await tester.pump();
      expect(find.byType(PlayerStage), findsOneWidget);
    });

    testWidgets('全屏页画面铺满并提供返回与弹幕设置入口', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      await tester
          .pumpWidget(MaterialApp(home: FullscreenPlayerPage(controller: c)));
      await tester.pump();

      final stage = tester.widget<PlayerStage>(find.byType(PlayerStage));
      expect(stage.fullscreen, isTrue);
      expect(
        find.descendant(
          of: find.byType(PlayerStage),
          matching: find.byType(AspectRatio),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byType(PlayerControls), findsOneWidget);
    });
  });
}
