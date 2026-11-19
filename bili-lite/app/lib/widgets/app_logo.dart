import 'package:flutter/material.dart';

import '../core/theme.dart';

/// App 标志。
///
/// 扁平化后改为纯粉 squircle + 白色「bi」字标，
/// 去掉渐变、外发光与文字阴影。
class AppLogo extends StatelessWidget {
  const AppLogo({Key? key, this.size = 38}) : super(key: key);

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.pink,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Center(
        child: Text(
          'bi',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.47,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1,
          ),
        ),
      ),
    );
  }
}
