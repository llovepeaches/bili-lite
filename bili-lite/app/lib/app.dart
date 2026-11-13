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
          // Web 的 html renderer 关掉真实背景模糊，用渐变与镜面高光模拟折射；
          // 原生端开启真实 blur。
          blur: appState.glassEnabled && !kIsWeb
              ? 16.0 * appState.glassStrength
              : 0.0,
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
