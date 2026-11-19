import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 普通文字。
///
/// 历史上这个组件会在玻璃上叠一层白色 shadow 来保证可读性；
/// 扁平化后卡片和背景都是实色，不再需要任何光晕，
/// 这里只保留组件名与构造参数，直接渲染普通 [Text]。
class GlassText extends StatelessWidget {
  const GlassText(
    this.text, {
    Key? key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
  }) : super(key: key);

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style ?? AppTextStyles.body(context),
    );
  }
}
