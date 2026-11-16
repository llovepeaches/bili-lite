import 'package:bililite/rendering/render_lens_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [RenderLensBackdrop] 的支点换算测试。
///
/// 背景事实（原生 Linux Skia 实测，见 docs/重构说明.md）：
///
/// * `ImageFilter.matrix` 的 src/dest 位于**滤镜所在的空间**，也就是
///   最近一层 `RepaintBoundary` 祖先的局部空间；
/// * 映射方向是 `dest = pivot + s · (src − pivot)`（以支点为不动点）；
/// * 单位是逻辑像素。
///
/// 下面用一个「玻璃嵌在有偏移的 RepaintBoundary 里」的布局验证：
/// 支点必须落在该 boundary 的局部空间，而不是屏幕坐标 —— 否则透镜
/// 会把背景往错误的方向拉。
void main() {
  testWidgets('支点换算到 RepaintBoundary 祖先的局部空间', (tester) async {
    final GlobalKey glassKey = GlobalKey();
    final GlobalKey boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: <Widget>[
            Positioned(
              left: 100,
              top: 100,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 160,
                  height: 200,
                  child: RenderLensBackdropHost(
                    key: glassKey,
                    lens: 1.25,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final RenderBox glass =
        glassKey.currentContext!.findRenderObject()! as RenderBox;
    final RenderBox boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderBox;

    // 支点应等于「玻璃中心在边界局部空间里的位置」。
    final Offset globalCenter = glass.localToGlobal(glass.size.center(Offset.zero));
    final Offset boundaryOrigin = boundary.localToGlobal(Offset.zero);
    final Offset expected = globalCenter - boundaryOrigin;

    final RenderLensBackdrop ro =
        glassKey.currentContext!.findRenderObject()! as RenderLensBackdrop;
    final Offset actual = ro.pivotInFilterSpace;

    expect(actual.dx, closeTo(expected.dx, 0.5));
    expect(actual.dy, closeTo(expected.dy, 0.5));

    // 关键：支点不等于屏幕坐标 —— 差值正好是边界的原点偏移。
    expect((actual - globalCenter).dx, closeTo(-boundaryOrigin.dx, 0.5));
    expect(actual.dx, isNot(closeTo(globalCenter.dx, 1)));
  });

  testWidgets('无 RepaintBoundary 祖先时支点即屏幕坐标下的玻璃中心',
      (tester) async {
    final GlobalKey glassKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 160,
            height: 200,
            child: RenderLensBackdropHost(
              key: glassKey,
              lens: 1.25,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderBox glass =
        glassKey.currentContext!.findRenderObject()! as RenderBox;
    final RenderLensBackdrop ro =
        glassKey.currentContext!.findRenderObject()! as RenderLensBackdrop;

    final Offset globalCenter = glass.localToGlobal(glass.size.center(Offset.zero));
    expect(ro.pivotInFilterSpace.dx, closeTo(globalCenter.dx, 0.5));
    expect(ro.pivotInFilterSpace.dy, closeTo(globalCenter.dy, 0.5));
  });

  testWidgets('透镜把支点外的采样点按倍率推离支点', (tester) async {
    // 以支点为不动点：p' = pivot + s · (p − pivot)
    const double s = 1.25;
    const Offset pivot = Offset(80, 100);
    const Offset p = Offset(130, 100);
    final Offset moved = pivot + (p - pivot) * s;
    expect(moved.dx, closeTo(142.5, 1e-9));
    expect(moved.dy, closeTo(100, 1e-9));
  });

  testWidgets('lens 与 sigma 可在运行期更新', (tester) async {
    final GlobalKey glassKey = GlobalKey();

    Widget build(double lens, double sigma) {
      return MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: RenderLensBackdropHost(
            key: glassKey,
            lens: lens,
            sigma: sigma,
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(1.0, 4));
    RenderLensBackdrop ro =
        glassKey.currentContext!.findRenderObject()! as RenderLensBackdrop;
    expect(ro.lens, 1.0);
    expect(ro.sigma, 4);

    await tester.pumpWidget(build(1.2, 9));
    ro = glassKey.currentContext!.findRenderObject()! as RenderLensBackdrop;
    expect(ro.lens, 1.2);
    expect(ro.sigma, 9);
  });
}

/// 测试用宿主：把 [RenderLensBackdrop] 暴露成可被 key 定位的 widget。
class RenderLensBackdropHost extends SingleChildRenderObjectWidget {
  const RenderLensBackdropHost({
    Key? key,
    required this.lens,
    this.sigma = 8,
    Widget? child,
  }) : super(key: key, child: child);

  final double lens;
  final double sigma;

  @override
  RenderLensBackdrop createRenderObject(BuildContext context) =>
      RenderLensBackdrop(sigma: sigma, lens: lens);

  @override
  void updateRenderObject(
      BuildContext context, RenderLensBackdrop renderObject) {
    renderObject
      ..lens = lens
      ..sigma = sigma;
  }
}
