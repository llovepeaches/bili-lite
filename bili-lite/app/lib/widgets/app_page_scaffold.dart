import 'package:flutter/material.dart';

import 'glass.dart';

/// 应用内普通页面的统一骨架。
///
/// 这里不改变任何视觉参数，只把各页面重复写的
/// `Scaffold + AppBar + GlassBar` 收拢到一处。需要特殊 AppBar 的页面
/// （例如透明背景的播放页）仍可直接使用 [Scaffold]。
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    Key? key,
    required this.title,
    required this.body,
    this.actions,
    this.bottom,
    this.titleSpacing,
  }) : super(key: key);

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? titleSpacing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: titleSpacing,
        flexibleSpace: const GlassBar(),
        title: title,
        actions: actions,
        bottom: bottom,
      ),
      body: body,
    );
  }
}
