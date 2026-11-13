import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import 'glass.dart';

/// App 标志。
///
/// 重构前这个圆形粉色「bi」标记在两处各写了一遍：`shell_page.dart` 的 `_Logo`
///（38pt）和 `home_page.dart` 的 `_GlassLogo`（28pt），除了尺寸没有任何区别。
/// 现在统一成一个组件，尺寸由调用方指定。
class AppLogo extends StatelessWidget {
  const AppLogo({Key? key, this.size = 38}) : super(key: key);

  final double size;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.pill,
      padding: EdgeInsets.zero,
      tint: AppColors.pink,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            'bi',
            style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.47,
                fontWeight: FontWeight.w800,
                letterSpacing: -1),
          ),
        ),
      ),
    );
  }
}
