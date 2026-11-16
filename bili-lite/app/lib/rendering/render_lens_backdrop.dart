import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/glass_optics.dart';

/// 带透镜折射的背景采样层。
///
/// 相比 `BackdropFilter` 有两处关键差别：
///
/// 1. **滤镜在 paint 阶段构造**。`BackdropFilter` 的 filter 是构造期常量，
///    而透镜支点必须知道「玻璃中心在**滤镜坐标空间**里的位置」——
///    这个值只有渲染阶段才知道（`paint` 拿到的 offset 链）。
///    这里用 [getTransformTo] 把玻璃中心换算到 backdrop 采样空间，
///    再交给 [GlassOptics.magnify] 构造矩阵。
///
/// 2. **不套 `RepaintBoundary`**。`RepaintBoundary` 会为该子树建立独立的
///    渲染表面，backdrop 采样只能看到**同一 surface 内**、在本层之前绘制
///    的内容。实测（原生 Linux Skia，同一画面左右对照）：
///    玻璃外套 `RepaintBoundary` 的一侧完全看不到背后的黑条，
///    不套的一侧正常透出 —— 给玻璃自己套一层等于把背景全隔离掉，
///    玻璃会退化成一块不透明的浅色板。
///
/// 采样内容与滤镜坐标系的空间关系（实测 Flutter 3.0 / Skia）：
/// * backdrop 采样到的是「本层之前、在同一合成上下文里画过的内容」；
/// * `ImageFilter.matrix` 的 src/dest 位于**滤镜所在的空间**，也就是
///   最近一层 `RepaintBoundary` 祖先的局部空间（没有则为根空间）。
///
/// 因此支点的正确算法是：把玻璃中心变换到「最近 RepaintBoundary 祖先」
/// 的局部空间；若找不到祖先，就用根空间（即屏幕坐标）。
class RenderLensBackdrop extends RenderProxyBox {
  RenderLensBackdrop({
    RenderBox? child,
    required double sigma,
    required double lens,
  })  : _sigma = sigma,
        _lens = lens,
        super(child);

  double _sigma;
  double _lens;

  double get sigma => _sigma;
  set sigma(double value) {
    if (_sigma == value) return;
    _sigma = value;
    markNeedsPaint();
  }

  double get lens => _lens;
  set lens(double value) {
    if (_lens == value) return;
    _lens = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    assert(needsCompositing);

    // 支点：玻璃中心在「滤镜坐标空间」里的位置。
    final Offset pivot = pivotInFilterSpace;

    final ui.ImageFilter filter = GlassOptics.navFilter(
      sigma: _sigma,
      lens: _lens,
      pivot: pivot,
    );

    final BackdropFilterLayer? bfl = layer as BackdropFilterLayer?;
    if (bfl == null) {
      layer = BackdropFilterLayer();
    }
    final BackdropFilterLayer l = layer! as BackdropFilterLayer;
    l.filter = filter;
    l.blendMode = BlendMode.srcOver;
    context.pushLayer(l, super.paint, offset);
  }

  /// 把玻璃中心换算到滤镜坐标空间。
  ///
  /// 公开出来是为了让单测能直接断言支点落在哪个空间里 ——
  /// 这是整块透镜最容易出错的地方（拿屏幕坐标当支点会让玻璃整体漂移）。
  Offset get pivotInFilterSpace {
    final RenderObject? target = _backdropSpaceAnchor();
    final Matrix4 transform = getTransformTo(target);
    return MatrixUtils.transformPoint(
      transform,
      size.center(Offset.zero),
    );
  }

  /// 滤镜坐标空间的锚点：最近一层 `RepaintBoundary` 祖先。
  /// 没有则退回根（`null`），此时坐标空间即屏幕坐标。
  RenderObject? _backdropSpaceAnchor() {
    RenderObject? node = parent as RenderObject?;
    while (node != null) {
      if (node is RenderRepaintBoundary) return node;
      node = node.parent as RenderObject?;
    }
    return null;
  }
}
