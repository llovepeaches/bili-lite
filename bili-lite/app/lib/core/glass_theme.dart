import 'package:flutter/material.dart';

import 'theme.dart';

/// 液态玻璃的全局配置。由 app.dart 在 MaterialApp.builder 里根据 AppState 组装，
/// 通过 GlassScope 下发给整棵页面树，改动时只重建依赖它的玻璃组件。
class GlassConfig {
  const GlassConfig({
    required this.enabled,
    required this.strength,
    required this.motion,
    required this.blur,
    this.tinted = false,
  });

  /// 总开关：关闭后所有玻璃组件退化为原来的不透明卡片，Aurora 背景消失。
  final bool enabled;

  /// 材质浓度 0.45 / 0.75 / 1.0，控制不透明度、高光与阴影强度。
  final double strength;

  /// 背景光晕与镜面高光是否缓慢漂移。
  final bool motion;

  /// 真实背景模糊 sigma。Web 的 html renderer 下置 0，靠渐变与高光模拟折射。
  final double blur;

  /// iOS 26.1 的「通透 Clear / 着色 Tinted」材质。
  /// 通透档内部几乎全透，仅靠沿边缘的折射高光定义形状；
  /// 着色档抬高材质不透明度，换取更强的文字可读性。
  final bool tinted;

  static const GlassConfig fallback = GlassConfig(
    enabled: true,
    strength: 0.75,
    motion: false,
    blur: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassConfig &&
          other.enabled == enabled &&
          other.strength == strength &&
          other.motion == motion &&
          other.blur == blur &&
          other.tinted == tinted;

  @override
  int get hashCode => Object.hash(enabled, strength, motion, blur, tinted);
}

/// 把配置注入 widget 树；任意后代用 GlassTheme.of(context) 建立依赖。
class GlassScope extends InheritedWidget {
  const GlassScope({
    Key? key,
    required this.config,
    required Widget child,
  }) : super(key: key, child: child);

  final GlassConfig config;

  @override
  bool updateShouldNotify(GlassScope oldWidget) => oldWidget.config != config;
}

class GlassTheme {
  GlassTheme._();

  static GlassConfig of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GlassScope>();
    return scope?.config ?? GlassConfig.fallback;
  }
}

/// 全 App 唯一的镜面高光时钟。相位量化成 24 步，只有显式订阅的
/// 大面积玻璃（侧栏、dock、工具条）会随之重绘，卡片级玻璃保持静态，
/// 这样 Web 的 html renderer 下也不会因为几十个 painter 同时动画而掉帧。
class GlassClock extends InheritedNotifier<ValueNotifier<double>> {
  const GlassClock({
    Key? key,
    required ValueNotifier<double> notifier,
    required Widget child,
  }) : super(key: key, notifier: notifier, child: child);

  static ValueNotifier<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassClock>()?.notifier;
}

/// 一套随明暗主题与材质档切换的玻璃光学参数。
///
/// 与 iOS 26 Liquid Glass 对齐的设计要点：
/// 1. **内部近乎全透**：内容层透出来，玻璃只由边缘定义形状，不是白色亚克力板；
/// 2. **边缘外部高光**：沿形状轮廓一圈明亮高光，左上与右下最强（镜面反射）；
/// 3. **内侧折射环**：由外向内的亮度梯度，模拟光线在玻璃边缘被弯折、聚集（lensing）；
/// 4. **色散与镜面亮斑**：边缘一侧偏青、一侧偏粉，亮斑随交互/时间沿轮廓流动；
/// 5. **自适应明暗**：材质颜色取自背后内容，浅色与深色各有一套调色板；
/// 6. 关闭玻璃时退回完全不透明的原配色。
class GlassPalette {
  GlassPalette.of(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark,
        _s = GlassTheme.of(context).enabled
            ? 0.62 + 0.38 * GlassTheme.of(context).strength
            : 0.0,
        tinted = GlassTheme.of(context).tinted;

  GlassPalette(this.dark, this._s, {this.tinted = false});

  final bool dark;
  final double _s;
  final bool tinted;

  bool get isGlass => _s > 0;

  /// 通透档把内部填充压到很薄，着色档约翻倍。
  double get _body => (tinted ? 1.0 : 0.34) * _s;
  double get _pill => (tinted ? 1.0 : 0.62) * _s;

  // ---- 背景 ----
  LinearGradient get backdrop {
    if (!isGlass) {
      return LinearGradient(colors: <Color>[
        dark ? AppColors.darkBg : AppColors.lightBg,
        dark ? AppColors.darkBg : AppColors.lightBg,
      ]);
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const <Color>[Color(0xFF0A0C16), Color(0xFF171320), Color(0xFF081420)]
          : const <Color>[Color(0xFFF3F6FB), Color(0xFFFBF5F8), Color(0xFFF2F8FC)],
    );
  }

  double get auroraAlpha =>
      (dark ? 0.34 : 0.22) *
      (0.55 + 0.45 * (_s > 0 ? (_s - 0.62) / 0.38 : 0));

  // ---- 面板填充：内部尽可能透 ----
  Color get fillTop => dark
      ? const Color(0xFF141826).withOpacity(0.58 * _body)
      : Colors.white.withOpacity(0.86 * _body);

  Color get fillMid => dark
      ? const Color(0xFF2C3458).withOpacity(0.36 * _body)
      : const Color(0xFFE9F1FF).withOpacity(0.52 * _body);

  Color get fillBottom => dark
      ? const Color(0xFF0B0E18).withOpacity(0.66 * _body)
      : Colors.white.withOpacity(0.72 * _body);

  LinearGradient fill([Color? tint]) {
    if (tint == null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[fillTop, fillMid, fillBottom],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color.lerp(fillTop, tint, 0.30)!,
        Color.lerp(fillMid, tint, 0.20)!,
        Color.lerp(fillBottom, tint, 0.28)!,
      ],
    );
  }

  /// 外圈渐变描边：模拟镜片边缘被灯照亮的高光，两端最亮、中段带色偏。
  LinearGradient rim([Color? tint]) {
    final double a = (dark ? 0.66 : 0.98) * (0.55 + 0.45 * _s);
    if (tint == null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const <double>[0.0, 0.18, 0.5, 0.82, 1.0],
        colors: <Color>[
          Colors.white.withOpacity(a),
          Colors.white.withOpacity(a * 0.32),
          (dark ? AppColors.blue : AppColors.pink).withOpacity(a * 0.18),
          Colors.white.withOpacity(a * 0.26),
          Colors.white.withOpacity(a * 0.86),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const <double>[0.0, 0.5, 1.0],
      colors: <Color>[
        Colors.white.withOpacity(dark ? 0.62 : 0.98),
        tint.withOpacity(0.46),
        Colors.white.withOpacity(dark ? 0.18 : 0.64),
      ],
    );
  }

  // ---- 透镜光学参数 ----

  /// 沿形状外缘最亮的一圈高光。
  double get edgeHighlight => (dark ? 0.62 : 0.98) * (0.50 + 0.50 * _s);

  /// 内侧折射环的暗部强度（lensing 的边缘光线聚集）。
  double get lensShade => (dark ? 0.46 : 0.22) * (0.40 + 0.60 * _s);

  /// 沿轮廓流动的镜面亮斑亮度。
  double get specular => (dark ? 0.74 : 1.0) * (0.45 + 0.55 * _s);

  /// 边缘色散（青 / 粉分离）强度。
  double get dispersion => (dark ? 0.34 : 0.26) * (0.40 + 0.60 * _s);

  Color get causticWarm => AppColors.pink;
  Color get causticCool => AppColors.blue;

  // ---- 内部柔光（工具条仍用）----
  double get sheenAlpha => (dark ? 0.10 : 0.20) * _s;

  Color get innerShade => dark
      ? Colors.black.withOpacity(0.24 * _s)
      : const Color(0xFF6C6290).withOpacity(0.06 * _s);

  Color get innerRim => dark
      ? Colors.white.withOpacity(0.30 * _s)
      : Colors.white.withOpacity(0.92 * _s);

  // ---- 阴影 / 辉光 ----
  Color get shadow => dark
      ? Colors.black.withOpacity(0.42 * _s)
      : const Color(0xFF4A4370).withOpacity(0.14 * _s);

  Color get glow => AppColors.pink.withOpacity((dark ? 0.12 : 0.09) * _s);

  Color get glassLine => dark
      ? Colors.white.withOpacity(0.22)
      : Colors.white.withOpacity(0.92);

  Color get rimMid => dark
      ? Colors.white.withOpacity(0.24)
      : Colors.white.withOpacity(0.88);

  // ---- 小徽章 / 芯片 ----
  Color pillTop(Color? tint) => tint != null
      ? tint.withOpacity((tint.alpha / 255.0) * (tinted ? 0.96 : 0.74))
      : (dark
          ? Colors.white.withOpacity(0.20 * _pill)
          : Colors.white.withOpacity(0.66 * _pill));

  Color pillBottom(Color? tint) => tint != null
      ? Color.lerp(tint, dark ? Colors.black : Colors.white, 0.24)!
          .withOpacity((tint.alpha / 255.0) * (tinted ? 0.92 : 0.70))
      : (dark
          ? Colors.white.withOpacity(0.07 * _pill)
          : Colors.white.withOpacity(0.38 * _pill));

  Color pillRim(Color? tint) => tint != null
      ? Colors.white.withOpacity(0.72)
      : (dark ? Colors.white.withOpacity(0.44) : Colors.white.withOpacity(0.96));

  Color get selectedTop => AppColors.pink.withOpacity(0.44 * _s);
  Color get selectedBottom => AppColors.pink.withOpacity(0.16 * _s);
  Color get selectedRim => AppColors.pink.withOpacity(0.74);

  // ---- 关闭玻璃后的退化配色 ----
  Color get plainCard => dark ? AppColors.darkCard : Colors.white;
  Color get plainBorder => dark ? AppColors.darkLine : AppColors.lightLine;
}
