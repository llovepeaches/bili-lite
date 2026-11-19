import 'package:flutter/material.dart';

/// 静态分页容器：只显示 [index] 指定的页面，**不响应左右滑动切页**。
///
/// 与 `PageView` 不同，所有页面始终挂载在树里，首页滚动位置、搜索页输入
/// 等状态都会保留；页面切换只由外部导航（底栏 / 侧栏 / 返回键）驱动。
class PageStack extends StatelessWidget {
  const PageStack({
    Key? key,
    required this.pages,
    required this.index,
  }) : super(key: key);

  /// 页面列表，顺序即导航顺序。
  final List<Widget> pages;

  /// 当前显示的页面下标。
  final int index;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final int safeIndex =
        index < 0 ? 0 : (index >= pages.length ? pages.length - 1 : index);
    return IndexedStack(
      index: safeIndex,
      children: pages,
    );
  }
}
