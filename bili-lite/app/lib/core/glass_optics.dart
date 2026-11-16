import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Offset;

/// 真·液态玻璃的**光学层**：把「采样真实背景 → 模糊 → 透镜折射」
/// 这套 Compose Glass 的语义，翻译成当前平台真正能执行的滤镜链。
///
/// 平台能力边界（实测 Flutter 3.0，不是推测）：
///
/// * **原生（Skia）** —— `ImageFilter.compose` 与 `ImageFilter.matrix` 都可用。
///   透镜折射因此可以真的做出来：先对背景采样做模糊，再用 matrix 把
///   采样结果**放大**，等效于一块凸透镜把底下的内容顶大。
///   放大倍率越大越"鼓"，但也越容易看出背景被拉变形，1.04~1.08 是甜区。
///
/// * **Web（html renderer）** —— 引擎把 `BackdropFilter` 落成 CSS
///   `backdrop-filter: blur(...)`，**只认 blur**。一旦滤镜链里出现
///   matrix / compose，滤镜会被整体丢弃、玻璃退化成一层 20% 的黑色遮罩
///   （颜色发脏）。所以 Web 端只给纯 blur，透镜感交给手绘的折射环补。
///
/// 两个平台共用同一套调用方：平台差异全部收在这里，玻璃组件不用分支。
class GlassOptics {
  const GlassOptics._();

  /// 当前平台是否支持真·透镜折射（放大背景采样）。
  static bool get supportsLens => !kIsWeb;

  /// 导航级玻璃（底栏 / 顶栏 / 侧栏）的真实背景滤镜。
  ///
  /// [sigma] 是模糊半径（逻辑像素），[lens] 是透镜放大倍率，
  /// 1.0 表示不折射。
  ///
  /// [pivot] 是透镜支点，单位与 [sigma] 相同（逻辑像素），坐标系是
  /// **滤镜所在的坐标空间** —— 也就是最近一层 RepaintBoundary 的局部
  /// 空间。坐标空间这件事是像素级实测出来的，详见 [magnify]。
  static ui.ImageFilter navFilter({
    required double sigma,
    double lens = 1.0,
    Offset pivot = Offset.zero,
  }) {
    final ui.ImageFilter blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    if (!supportsLens || lens <= 1.001) return blur;
    // compose 的语义是 outer(inner(source))：先模糊，再放大。
    return ui.ImageFilter.compose(
      outer: magnify(lens, pivot),
      inner: blur,
    );
  }

  /// 以 [pivot] 为不动点，把采样背景放大 [scale] 倍。
  ///
  /// matrix 是 4×4 仿射矩阵（列主序）。实测 Flutter 3.0 / Skia 下
  /// `ImageFilter.matrix` 的映射是 **dest = s · src + t**，单位为逻辑像素。
  ///
  /// 坐标系（实测结论，容易踩坑）：`src` / `dest` 都在**滤镜所在的空间**里，
  /// 也就是**离它最近的那层 RepaintBoundary 的局部空间** ——
  /// 既不是控件自身的局部坐标，也不是屏幕全局坐标。
  /// 把滤镜控件在屏幕上挪来挪去，采样结果完全不变；而一旦给祖先套一层
  /// `RepaintBoundary`，采样坐标就跟着那层 boundary 的原点走。
  ///
  /// 因此：**透镜支点必须换算到滤镜所在空间**。最省事的做法是给玻璃
  /// 套一层自己的 `RepaintBoundary`，此时滤镜空间 == 玻璃局部空间，
  /// 支点直接取 `size.center(Offset.zero)` 即可。
  ///
  /// 要让支点 p 不动：s·p + t = p ⇒ t = p·(1 − s)。
  static ui.ImageFilter magnify(double scale, Offset pivot) {
    final Float64List m = Float64List(16);
    m[0] = scale; // x 缩放
    m[5] = scale; // y 缩放
    m[10] = 1.0; // z
    m[15] = 1.0; // w
    // 保持支点不动：p' = s·p + p·(1 − s)
    m[12] = pivot.dx * (1.0 - scale);
    m[13] = pivot.dy * (1.0 - scale);
    return ui.ImageFilter.matrix(m, filterQuality: ui.FilterQuality.medium);
  }
}
