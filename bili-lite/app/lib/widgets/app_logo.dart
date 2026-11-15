import 'package:flutter/material.dart';

/// App 标志（v0.1.0 品牌重绘）。
///
/// 与桌面 / 移动端启动图标来自同一套视觉：粉→紫对角渐变 squircle +
/// 白色粗体「bi」字标。之前这里是圆形玻璃片 + 纯色粉底，与各平台默认的
/// Flutter 蓝色「F」图标毫无关联；重绘后应用内外保持一致。
///
/// 尺寸由调用方指定，`shell_page.dart` 用 38pt、首页用 28pt。
class AppLogo extends StatelessWidget {
  const AppLogo({Key? key, this.size = 38}) : super(key: key);

  final double size;

  static const List<Color> _gradient = <Color>[
    Color(0xFFFFA6C9),
    Color(0xFFFB7299),
    Color(0xFF784ED6),
  ];

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.24;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradient,
          stops: <double>[0.0, 0.46, 1.0],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFB7299).withOpacity(0.28),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.08),
          ),
        ],
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
            shadows: <Shadow>[
              Shadow(
                color: const Color(0xFF4E1C6C).withOpacity(0.38),
                blurRadius: size * 0.06,
                offset: Offset(size * 0.02, size * 0.03),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
