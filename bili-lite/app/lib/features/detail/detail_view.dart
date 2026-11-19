import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/navigation.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/app_page_scaffold.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_text.dart';
import '../../widgets/segmented_switch.dart';
import '../../widgets/state_views.dart';
import '../account/login_gate.dart';
import 'detail_components.dart';
import 'detail_controller.dart';
import 'detail_extras.dart';

export 'detail_external.dart';

/// 视频详情视图。
///
/// 版式参考 MiniBili 的详情页：封面 → 「详情 / 评论」分段控件 → 内容，
/// 内容区依次是标题、BV 号、统计、UP 主卡片、四连互动栏、全文简介与话题标签。
/// 数据与分页在 [DetailController] 里；可复用卡片在 `detail_components.dart`，
/// 外链兜底在 `detail_external.dart`。本文件只负责页面骨架和内容编排。
class VideoDetailView extends StatefulWidget {
  const VideoDetailView({Key? key, required this.video}) : super(key: key);

  final Video video;

  @override
  State<VideoDetailView> createState() => _VideoDetailViewState();
}

class _VideoDetailViewState extends State<VideoDetailView> {
  late final DetailController _controller;

  /// 0 = 详情，1 = 评论。
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    _controller = DetailController(video: widget.video);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 同 HomeView：AnimatedBuilder 只包 body。
    // 整页重建会让玻璃条的镜面高光动画反复重播，表现为整页蒙一层白纱。
    return AppPageScaffold(
      title: const Text('视频详情', style: TextStyle(fontSize: 17)),
      actions: <Widget>[
        DetailToolGroup(controller: _controller),
        const SizedBox(width: 8),
      ],
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
          final twoColumn = Breakpoints.detailTwoColumn(constraints.maxWidth);
          if (twoColumn) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    // 宽屏是「左详情 + 右评论」双栏，封面与播放入口
                    // 归入左栏，否则宽屏下会完全看不到视频画面。
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildPlayer(),
                        const SizedBox(height: 16),
                        _buildDetail(),
                      ],
                    ),
                  ),
                ),
                const GlassDivider(vertical: true, thickness: 1),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildComments(),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                // 窄屏（尤其是横屏手机）下 16:9 播放器会占满整屏，
                // 把详情挤到看不见的地方。这里限制播放器高度不超过
                // 可用高度的一半，保证下方内容始终有一部分露出来。
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.5,
                  ),
                  child: _buildPlayer(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: GlassSegmented(
                  labels: const <String>['详情', '评论'],
                  index: _segment,
                  onChanged: (i) => setState(() => _segment = i),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _segment == 0
                      ? _buildDetailScroll()
                      : _buildCommentsScroll(),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ─────────────────────────── 详情 ───────────────────────────

  Widget _buildDetailScroll() {
    return SingleChildScrollView(
      key: const ValueKey<String>('detail'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final sub = context.subTextColor;
    final v = _controller.resolvedVideo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GlassText(
          v.title.isEmpty ? '（无标题）' : v.title,
          style: AppTextStyles.detailTitle(context),
        ),
        const SizedBox(height: 12),

        // 内容指标（播放 / 弹幕 / 评论）在上，互动指标交给下方互动栏。
        Row(
          children: <Widget>[
            DetailStat(Icons.play_circle_outline, v.stat.view, '播放'),
            const SizedBox(width: AppSpacing.lg),
            DetailStat(Icons.subtitles_outlined, v.stat.danmaku, '弹幕'),
            const SizedBox(width: AppSpacing.lg),
            DetailStat(Icons.mode_comment_outlined, v.stat.reply, '评论'),
          ],
        ),
        const SizedBox(height: 10),
        if (v.bvid.isNotEmpty) ...<Widget>[
          BvBadge(bvid: v.bvid),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Icon(Icons.schedule_outlined,
                size: 13, color: AppTextColor.tertiary(context)),
            const SizedBox(width: 4),
            Text(Fmt.relative(v.pubdate),
                style: AppTextStyles.caption(context)),
            if (v.tname.isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Icon(Icons.category_outlined,
                  size: 13, color: AppTextColor.tertiary(context)),
              const SizedBox(width: 4),
              Text(v.tname, style: AppTextStyles.caption(context)),
            ],
            const Spacer(),
            SourceBadge(source: _controller.source),
          ],
        ),
        const SizedBox(height: 16),

        DetailOwnerCard(video: v, onTap: () => _openSpace(v.owner)),
        const SizedBox(height: 14),

        DetailInteractionBar(controller: _controller, video: v),
        const SizedBox(height: 16),

        if (_controller.desc.isNotEmpty) ...<Widget>[
          DetailDescriptionCard(controller: _controller),
          const SizedBox(height: 12),
        ],

        if (_controller.tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _controller.tags
                .map((tag) => GlassPill(
                      radius: 9,
                      tint: AppColors.pink.withOpacity(0.16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: Text('#$tag',
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.pink,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
        ],

        if (_controller.pages.length > 1) ...<Widget>[
          SectionTitle(
            title: '分 P · ${_controller.pages.length}',
            trailing: Text('共 ${_controller.pages.length} 集',
                style: TextStyle(fontSize: 11, color: sub)),
          ),
          ..._controller.pages.map((p) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: GlassPill(
                  radius: 13,
                  tint: AppColors.pink.withOpacity(0.18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text('${p.page}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.pink,
                          fontWeight: FontWeight.w700)),
                ),
                title: Text(p.part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
                trailing: Text(p.durationText,
                    style: TextStyle(fontSize: 11, color: sub)),
              )),
        ],

        if (_controller.detailError != null) ...<Widget>[
          const SizedBox(height: 10),
          Text('详情补充失败：${_controller.detailError}',
              style: TextStyle(fontSize: 11, color: Colors.orange)),
        ],
      ],
    );
  }

  // ─────────────────────────── 播放器 ───────────────────────────

  Widget _buildPlayer() {
    final v = _controller.resolvedVideo;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 播放入口只保留这一个，避免父子手势同时命中把两个 PlayerPage
        // 叠进导航栈。
        onTap: () => openPlayer(context, v),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CoverImage(url: v.cover, radius: 14),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                ),
              ),
            ),
            Center(
              child: IgnorePointer(
                child: GlassCircleButton(
                  icon: Icons.play_arrow_rounded,
                  size: 58,
                  onTap: () {},
                ),
              ),
            ),
            if (v.durationText.isNotEmpty)
              Positioned(
                right: 10,
                bottom: 10,
                child: GlassPill(
                  radius: 7,
                  onDark: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(v.durationText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── 评论 ───────────────────────────

  Widget _buildCommentsScroll() {
    return SingleChildScrollView(
      key: const ValueKey<String>('comments'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: _buildComments(),
    );
  }

  Widget _buildComments() {
    final sub = context.subTextColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const GlassAccent(),
            const SizedBox(width: 8),
            const Text('评论',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(
              _controller.commentCount > 0
                  ? Fmt.compact(_controller.commentCount)
                  : '',
              style: TextStyle(fontSize: 12, color: sub),
            ),
            const Spacer(),
            DetailSortChip(
                label: '热门',
                value: 2,
                current: _controller.sort,
                onTap: _controller.changeSort),
            const SizedBox(width: 6),
            DetailSortChip(
                label: '最新',
                value: 0,
                current: _controller.sort,
                onTap: _controller.changeSort),
          ],
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: double.infinity,
          child: LoginRequiredHint(feature: '完整评论'),
        ),
        if (_controller.loadingComments && _controller.comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_controller.commentError != null &&
            _controller.comments.isEmpty)
          ErrorView(
            message: _controller.commentError!,
            onRetry: () => _controller.loadComments(refresh: true),
            compact: true,
          )
        else if (_controller.comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
                child: Text('暂时没有评论',
                    style: TextStyle(fontSize: 12.5, color: sub))),
          )
        else
          Column(
            children: _controller.comments
                .map((c) => DetailCommentCard(comment: c))
                .toList(),
          ),
        if (_controller.comments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: _controller.loadingMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : GlassChip(
                    label: '加载更多评论',
                    icon: Icons.expand_more_rounded,
                    tint: AppColors.pink,
                    radius: 12,
                    onTap: () => _controller.loadComments(more: true),
                  ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────── 跳转 ───────────────────────────

  /// 在应用内打开 UP 主空间，不再跳系统浏览器。
  Future<void> _openSpace(Owner owner) async {
    await openSpace(context, owner);
  }
}
