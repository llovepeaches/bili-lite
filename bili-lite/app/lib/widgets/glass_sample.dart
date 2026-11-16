import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/glass_optics.dart';
import '../rendering/render_lens_backdrop.dart';

/// 真实背景采样容器：把「采样 → 模糊 → 透镜折射」这条滤镜链包起来，
/// 并解决透镜支点的坐标系问题。
///
/// 用自定义的 [RenderLensBackdrop] 而不是 `BackdropFilter`，原因有两条：
///
/// 1. **支点必须在渲染阶段算**。`ImageFilter.matrix` 的 src/dest 位于
///    「滤镜所在的空间」—— 最近一层 `RepaintBoundary` 祖先的局部空间
///    （实测 Flutter 3.0 / Skia）。这个值只有 paint 阶段才知道，
///    所以滤镜必须在 paint 里构造。
/// 2. **不能给玻璃套 `RepaintBoundary`**。Flutter 会为 boundary 子树
///    建立独立渲染表面，backdrop 采样只能看到同一 surface 内、在本层
///    之前绘制的内容 —— 给玻璃自己套一层等于把背景全隔离掉，
///    玻璃会退化成一块不透明浅色板。
///
/// 顺带一提：`BackdropFilter` 采样的是它**之前**绘制的内容，
/// 这正好对应 Compose 里 `rememberLayerBackdrop { drawContent() }` 的语义。
class GlassSample extends StatelessWidget {
  const GlassSample({
    Key? key,
    required this.child,
    required this.sigma,
    this.lens = 1.0,
  }) : super(key: key);

  final Widget child;

  /// 模糊半径（逻辑像素）。
  final double sigma;

  /// 透镜放大倍率，1.0 表示不折射。
  final double lens;

  @override
  Widget build(BuildContext context) {
    // Web 的 html renderer 只认 CSS blur：滤镜链里混入 matrix 会让整个
    // 滤镜被丢弃、玻璃退化成一层黑纱。所以 Web 端走标准 `BackdropFilter`
    // （引擎会把它落成 DOM 的 `flt-backdrop-filter`），不做透镜折射。
    if (!GlassOptics.supportsLens) {
      return BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      );
    }
    return _GlassSampleRenderObjectWidget(
      sigma: sigma,
      lens: lens,
      child: child,
    );
  }
}

class _GlassSampleRenderObjectWidget extends SingleChildRenderObjectWidget {
  const _GlassSampleRenderObjectWidget({
    Key? key,
    required this.sigma,
    required this.lens,
    Widget? child,
  }) : super(key: key, child: child);

  final double sigma;
  final double lens;

  @override
  RenderLensBackdrop createRenderObject(BuildContext context) {
    return RenderLensBackdrop(sigma: sigma, lens: lens);
  }

  @override
  void updateRenderObject(BuildContext context, RenderLensBackdrop renderObject) {
    renderObject
      ..sigma = sigma
      ..lens = lens;
  }
}

/// 只要滤镜、不需要额外语义的场合（例如纯 blur 的卡片级玻璃）。
class GlassBlur extends StatelessWidget {
  const GlassBlur({Key? key, required this.child, required this.sigma})
      : super(key: key);

  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
