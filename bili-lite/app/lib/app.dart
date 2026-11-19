import 'package:flutter/material.dart';

import 'core/glass_theme.dart';
import 'core/theme.dart';
import 'features/shell/shell_page.dart';
import 'router/app_routes.dart';
import 'state/globals.dart';

class BiliLiteApp extends StatelessWidget {
  const BiliLiteApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        // 扁平化后不再需要镜面时钟、极光背景与光学参数；
        // 这里只保留一个关闭态的配置，供历史兼容 API 读取。
        const GlassConfig flatConfig = GlassConfig(
          enabled: false,
          strength: 0,
          motion: false,
          blur: 0,
        );

        return MaterialApp(
          title: 'Bili Lite',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: appState.themeMode,
          // 集中路由表：所有页面跳转都登记在 AppRouter 里，
          // 这里只做一次挂接，避免各页面各写一份 MaterialPageRoute。
          onGenerateRoute: AppRouter.generate,
          builder: (context, child) => GlassScope(
            config: flatConfig,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: child ?? const SizedBox.shrink(),
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
