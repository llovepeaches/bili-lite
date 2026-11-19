import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/app_page_scaffold.dart';
import '../account/login_gate.dart';
import 'space_cards.dart';
import 'space_controller.dart';

/// 应用内 UP 主空间。
///
/// 「查看主页」原先直接 `launchUrl` 跳系统浏览器，用户一点击就离开 App。
/// 现在改成命名路由在应用内打开：先展示 UP 主资料，再列出检索到的该 UP 主
/// 稿件，点击任一稿件走 `openVideoDetail` 留在应用内。
///
/// 数据边界（不编造内容）：B 站的空间投稿接口对匿名请求返回 -403 / 风控 HTML，
/// 所以这里复用已经验证可用的站内搜索接口按 UP 主名称检索，再按 mid 过滤，
/// 只展示确实属于该 UP 主的稿件；检索不到就如实显示空态。
///
/// 请求与列表状态在 [SpaceController]，卡片在 `space_cards.dart`，
/// 本文件只负责页面骨架与状态分支。
class SpaceView extends StatefulWidget {
  const SpaceView({Key? key, required this.owner}) : super(key: key);

  final Owner owner;

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  late final SpaceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SpaceController(owner: widget.owner);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: Text(
        widget.owner.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => RefreshIndicator(
          color: AppColors.pink,
          onRefresh: _controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              SpaceOwnerCard(owner: widget.owner),
              const SizedBox(height: 12),
              const LoginRequiredHint(feature: 'UP 主完整稿件与评论'),
              if (_controller.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_controller.error != null)
                SpaceNotice(message: '稿件加载失败，下拉可重试', onRetry: _controller.load)
              else if (_controller.videos.isEmpty)
                SpaceNotice(
                    message: '暂未检索到该 UP 主的稿件', onRetry: _controller.load)
              else ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 2),
                  child: Text(
                    '稿件 · ${_controller.videos.length}',
                    style: TextStyle(
                        fontSize: 12,
                        color: context.subTextColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                ..._controller.videos
                    .map((v) => SpaceVideoRow(video: v))
                    .toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
