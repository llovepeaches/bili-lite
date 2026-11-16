import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/glass_theme.dart';
import 'core/theme.dart';
import 'features/shell/shell_page.dart';
import 'router/app_routes.dart';
import 'state/globals.dart';
import 'widgets/glass.dart';

class BiliLiteApp extends StatefulWidget {
  const BiliLiteApp({Key? key}) : super(key: key);

  @override
  State<BiliLiteApp> createState() => _BiliLiteAppState();
}

class _BiliLiteAppState extends State<BiliLiteApp>
    with SingleTickerProviderStateMixin {
  /// 全 App 唯一的镜面高光时钟，量化成 24 步。
  final ValueNotifier<double> _clock = ValueNotifier<double>(0.12);
  AnimationController? _ticker;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..addListener(() {
        final v = (_ticker!.value * 24).roundToDouble() / 24;
        if (_clock.value != v) _clock.value = v;
      });
  }

  void _sync(bool motion) {
    final ticker = _ticker;
    if (ticker == null) return;
    if (motion && !_running) {
      ticker.repeat();
      _running = true;
    } else if (!motion && _running) {
      ticker.stop();
      _running = false;
      _clock.value = 0.12;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final config = GlassConfig(
          enabled: appState.glassEnabled,
          strength: appState.glassStrength,
          motion: appState.glassMotion,
          tinted: appState.glassTinted,
          // 卡片级模糊：Web 的 html renderer 下关掉 —— 一页几十张卡片，
          // 每张都做一次 backdrop 采样会明显掉帧。
          blur: appState.glassEnabled && !kIsWeb
              ? 16.0 * appState.glassStrength
              : 0.0,
          // 导航级模糊：底栏 / 顶栏 / 侧栏只有几件大面积玻璃，采样收益最高。
          //
          // Web 的 html renderer **支持** BackdropFilter —— 引擎把它落成
          // CSS `backdrop-filter: blur()`（实测 DOM 里确实生成了
          // `flt-backdrop-filter` 且带 backdrop-filter 样式），所以两端都能开。
          navBlur: appState.glassEnabled
              ? 18.0 * appState.glassStrength
              : 0.0,
          // 透镜折射：只有原生端（Skia）能真正把背景采样放大。
          // Web 的 html renderer 只认 blur 类滤镜，混入 matrix 会让滤镜
          // 被丢弃、玻璃退化成一层黑纱，所以那边给 1.0（不折射）。
          lens: appState.glassEnabled && !kIsWeb ? 1.06 : 1.0,
          // 玻璃表面的白色覆盖层，对应 Compose Glass 的
          // `onDrawSurface = { drawRect(Color.White.copy(alpha = 0.5f)) }`。
          surface: appState.glassEnabled ? 0.16 * appState.glassStrength : 0.0,
          // 玻璃的色相染色：对应 Compose 参考实现里
          // `drawRect(tint, blendMode = BlendMode.Hue)` 那一层。
          // 底栏是「透镜 + 染色」的组合，所以这里给一个冷蓝 ——
          // 跟应用主色的粉形成冷暖对比，玻璃因此更像一块有色的实体。
          hue: appState.glassEnabled ? const Color(0xFF0088FF) : null,
          hueAlpha: appState.glassEnabled ? 0.06 * appState.glassStrength : 0.0,
          // Hue 混合层自身也要半透明 —— 不透明的话色相被整体替换，
          // 玻璃会退化成一整块不透明的蓝色板，背景一点也透不出来。
          hueMix: appState.glassEnabled ? 0.22 * appState.glassStrength : 0.0,
        );
        _sync(config.enabled && config.motion);

        return MaterialApp(
          title: 'Bili Lite',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: appState.themeMode,
          // 集中路由表：所有页面跳转都登记在 AppRouter 里，
          // 这里只做一次挂接，避免各页面各写一份 MaterialPageRoute。
          onGenerateRoute: AppRouter.generate,
          // 全局三层：极光背景 → 玻璃作用域/镜面时钟 → 页面（透明 Scaffold）。
          builder: (context, child) => GlassScope(
            config: config,
            child: GlassClock(
              notifier: _clock,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  GlassBackdrop(config: config),
                  if (child != null) child,
                ],
              ),
            ),
          ),
          home: appState.initialized ? const ShellPage() : const _BootScreen(),
        );
      },
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
