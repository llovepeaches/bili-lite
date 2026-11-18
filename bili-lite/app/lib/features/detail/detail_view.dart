import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/navigation.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_text.dart';
import '../../widgets/segmented_switch.dart';
import '../../widgets/state_views.dart';
import '../account/login_gate.dart';
import 'detail_controller.dart';
import 'detail_extras.dart';

/// 视频详情视图。
///
/// 版式参考 MiniBili 的详情页：封面 → 「详情 / 评论」分段控件 → 内容，
/// 内容区依次是标题、BV 号、统计、UP 主卡片、四连互动栏、全文简介与话题标签。
/// 数据与分页在 [DetailController] 里。
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频详情', style: TextStyle(fontSize: 17)),
        flexibleSpace: const GlassBar(),
        actions: <Widget>[
          _ToolGroup(controller: _controller),
          const SizedBox(width: 8),
        ],
      ),
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
        // 标题
        GlassText(
          v.title.isEmpty ? '（无标题）' : v.title,
          style: AppTextStyles.detailTitle(context),
        ),
        const SizedBox(height: 12),

        // 统计行
        //
        // 上一版把 7 个指标（播放/弹幕/评论/点赞/投币/收藏/分享）平铺成
        // 同一行、同样式、同字号，结果是**没有一个指标能被优先看到** ——
        // 扫读时眼睛要在 7 个同权重数字之间平移。
        //
        // 现在按「内容指标 / 互动指标」分两层：
        //   * 内容指标（播放 / 弹幕 / 评论）—— 描述这个视频有多少人看，
        //     放在上面，字号更大、颜色更实；
        //   * 互动指标（点赞 / 投币 / 收藏 / 分享）—— 描述观众的反应，
        //     由下方的互动栏承担（有图标 + 可点击 + 状态反馈），
        //     这里不再重复，避免同一组数字出现两次。
        Row(
          children: <Widget>[
            _Stat(Icons.play_circle_outline, v.stat.view, '播放'),
            const SizedBox(width: AppSpacing.lg),
            _Stat(Icons.subtitles_outlined, v.stat.danmaku, '弹幕'),
            const SizedBox(width: AppSpacing.lg),
            _Stat(Icons.mode_comment_outlined, v.stat.reply, '评论'),
          ],
        ),
        const SizedBox(height: 10),
        if (v.bvid.isNotEmpty) ...<Widget>[
          BvBadge(bvid: v.bvid),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Icon(Icons.schedule_outlined, size: 13, color: AppTextColor.tertiary(context)),
            const SizedBox(width: 4),
            Text(Fmt.relative(v.pubdate),
                style: AppTextStyles.caption(context)),
            if (v.tname.isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Icon(Icons.category_outlined, size: 13, color: AppTextColor.tertiary(context)),
              const SizedBox(width: 4),
              Text(v.tname, style: AppTextStyles.caption(context)),
            ],
            const Spacer(),
            SourceBadge(source: _controller.source),
          ],
        ),
        const SizedBox(height: 16),

        // UP 主卡片
        _OwnerCard(video: v, onTap: () => _openSpace(v.owner)),
        const SizedBox(height: 14),

        // 四连互动栏
        _InteractionBar(controller: _controller, video: v),
        const SizedBox(height: 16),

        // 简介（全文，不折叠）
        if (_controller.desc.isNotEmpty) ...<Widget>[
          _DescriptionCard(controller: _controller),
          const SizedBox(height: 12),
        ],

        // 话题标签
        if (_controller.tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _controller.tags
                .map((tag) => GlassPill(
                      radius: 9,
                      tint: AppColors.pink.withOpacity(0.16),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

        // 分 P
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        // 播放入口只保留这一个。原先中央的 GlassCircleButton 也绑了一次
        // openPlayer，父子手势同时命中 / 快速连点会把两个 PlayerPage 叠进
        // 导航栈，返回一次还停在播放页，看起来就是「播放要二次打开」。
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
              // 纯视觉：点击统一交给外层 GestureDetector，
              // 避免同一区域注册两个互相抢手势的 onTap。
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
            _SortChip(
                label: '热门',
                value: 2,
                current: _controller.sort,
                onTap: _controller.changeSort),
            const SizedBox(width: 6),
            _SortChip(
                label: '最新',
                value: 0,
                current: _controller.sort,
                onTap: _controller.changeSort),
          ],
        ),
        const SizedBox(height: 8),
        // 评论是典型的「登录后才有完整数据」能力：未登录时给出原因与入口，
        // 已登录时这一行自动消失（原生直连请求也已带上登录 Cookie）。
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
                .map((c) => _CommentCard(comment: c))
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

/// 在系统浏览器里打开外链；打不开时复制链接兜底。
///
/// 详情页的「原站」「分享」「投币」等多处都要跳外链，抽成顶层函数后
/// 兜底提示只有一份，不会出现一处复制了链接、另一处静默失败。
Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  bool opened = false;
  try {
    if (await canLaunchUrl(uri)) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已复制链接，可粘贴到浏览器打开'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sheet)),
      ),
    );
  }
}

/// AppBar 右侧的胶囊工具组：收藏 / 稍后再看 / 播放 / 原站。
///
/// 改成一个玻璃胶囊把多个动作收在一起（MiniBili 的做法），
/// 而不是四个各自独立的圆形按钮 —— 后者在窄屏上会挤掉标题。
class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.controller});

  final DetailController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final video = controller.resolvedVideo;
          final favorite = library.isFavorite(video.bvid);
          final later = library.inWatchLater(video.bvid);
          return GlassPanel(
            radius: AppRadius.pill,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ToolButton(
                  icon: favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  tooltip: favorite ? '取消收藏' : '收藏',
                  active: favorite,
                  onTap: () => library.toggle(LibraryKind.favorites, video),
                ),
                _ToolButton(
                  icon: later
                      ? Icons.watch_later_rounded
                      : Icons.watch_later_outlined,
                  tooltip: later ? '移出稍后再看' : '稍后再看',
                  active: later,
                  onTap: () => library.toggle(LibraryKind.watchLater, video),
                ),
                _ToolButton(
                  icon: Icons.play_circle_outline_rounded,
                  tooltip: '应用内播放',
                  onTap: () => openPlayer(context, video),
                ),
                _ToolButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: '在官方客户端打开',
                  onTap: () => openExternal(context, video.webUrl),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 工具组里的单个图标按钮。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // 命中区做到 40×40（接近 44 的无障碍下限），图标仍是 19。
          // 上一版是 `horizontal: 6, vertical: 4`，实际热区只有 31×27，
          // 在触屏上很难点准 —— 顶栏挤了 4 个这种按钮，误触率很高。
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 19,
            color: active ? AppColors.pink : context.primaryTextColor,
          ),
        ),
      ),
    );
  }
}

/// UP 主卡片：头像 + 名字 + UID，右侧一个「查看主页」入口。
class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.video, required this.onTap});

  final Video video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: AppRadius.control + 2,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          UserAvatar(url: video.owner.face, name: video.owner.name, size: 42),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  video.owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('UID ${video.owner.mid}',
                    style: TextStyle(fontSize: 11, color: sub)),
              ],
            ),
          ),
          if (video.owner.mid.isNotEmpty)
            GlassChip(
              label: '查看主页',
              icon: Icons.person_outline_rounded,
              tint: AppColors.pink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelStyle: const TextStyle(fontSize: 12),
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

/// 四连互动栏：点赞 / 投币 / 收藏 / 分享。
///
/// 收藏是本地能力，直接切换本地状态；点赞、投币、分享属于 B 站侧的写操作，
/// 开放平台没有对应 scope，点击引导到官方客户端 —— 数值仍然如实展示。
class _InteractionBar extends StatelessWidget {
  const _InteractionBar({required this.controller, required this.video});

  final DetailController controller;
  final Video video;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final favorite = library.isFavorite(video.bvid);
        final later = library.inWatchLater(video.bvid);
        return Row(
          children: <Widget>[
            _InteractionItem(
              icon: Icons.thumb_up_off_alt_outlined,
              label: '点赞',
              value: video.stat.like,
              onTap: () => _openOfficial(context),
            ),
            _InteractionItem(
              icon: Icons.monetization_on_outlined,
              label: '投币',
              value: video.stat.coin,
              onTap: () => _openOfficial(context),
            ),
            _InteractionItem(
              icon: favorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              label: '收藏',
              value: video.stat.favorite,
              active: favorite,
              onTap: () => library.toggle(LibraryKind.favorites, video),
            ),
            _InteractionItem(
              icon: Icons.share_outlined,
              label: '分享',
              value: video.stat.share,
              onTap: () => showVideoShareSheet(
                context,
                video: video,
                onOpenExternal: (String url) => openExternal(context, url),
              ),
            ),
            const Spacer(),
            GlassChip(
              label: later ? '已在稍后再看' : '稍后再看',
              icon: Icons.watch_later_outlined,
              selected: later,
              tint: AppColors.pink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelStyle: const TextStyle(fontSize: 12),
              onTap: () => library.toggle(LibraryKind.watchLater, video),
            ),
          ],
        );
      },
    );
  }

  void _openOfficial(BuildContext context) {
    openExternal(context, video.webUrl);
  }
}

/// 互动栏里的单个条目：图标 + 数值。
class _InteractionItem extends StatelessWidget {
  const _InteractionItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 21,
                color: active ? AppColors.pink : context.primaryTextColor,
              ),
              const SizedBox(height: 4),
              Text(
                Fmt.compact(value),
                style: TextStyle(
                  fontSize: 10.5,
                  color: active ? AppColors.pink : sub,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 简介卡片：全文展示，不再折叠、不再显示展开按钮。
class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.controller});

  final DetailController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.control + 2,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('简介',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            controller.desc,
            style: TextStyle(
                fontSize: 13, height: 1.6, color: context.subTextColor),
          ),
        ],
      ),
    );
  }
}

/// 单个统计指标：图标 + 数值。
///
/// 上一版数值是 11.5 的灰字，和页面里其它说明文字完全一样重，
/// 于是「123.8万播放」这种最该被先看到的信息反而最不显眼。
/// 现在数值提到二级文字色、字号到 13，让内容指标比辅助说明更突出。
class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppTextColor.tertiary(context)),
          const SizedBox(width: 4),
          Text(
            Fmt.compact(value),
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w600,
              color: AppTextColor.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  final String label;
  final int value;
  final int current;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      labelStyle: const TextStyle(fontSize: 11.5),
      onTap: () => onTap(value),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UserAvatar(url: comment.avatar, name: comment.uname, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(comment.uname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pink)),
                      ),
                      if (comment.isTop) ...<Widget>[
                        const SizedBox(width: 6),
                        GlassPill(
                          radius: 4,
                          tint: AppColors.pink.withOpacity(0.18),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          child: const Text('置顶',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.pink,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      const Spacer(),
                      Text(Fmt.relative(comment.ctime),
                          style: TextStyle(fontSize: 10.5, color: sub)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(comment.message,
                      style: const TextStyle(fontSize: 13, height: 1.55)),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Icon(Icons.thumb_up_off_alt_outlined,
                          size: 12, color: sub),
                      const SizedBox(width: 3),
                      Text(Fmt.compact(comment.like),
                          style: TextStyle(fontSize: 10.5, color: sub)),
                      if (comment.replyCount > 0) ...<Widget>[
                        const SizedBox(width: 14),
                        Text('${Fmt.compact(comment.replyCount)} 条回复',
                            style: TextStyle(fontSize: 10.5, color: sub)),
                      ],
                      if (comment.location.isNotEmpty) ...<Widget>[
                        const Spacer(),
                        Text(comment.location,
                            style: TextStyle(fontSize: 10.5, color: sub)),
                      ],
                    ],
                  ),
                  if (comment.replies.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: GlassPanel(
                        radius: 12,
                        padding: const EdgeInsets.all(9),
                        showSheen: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: comment.replies
                              .map((r) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: RichText(
                                      text: TextSpan(
                                        style:
                                            TextStyle(fontSize: 11.5, color: sub),
                                        children: <TextSpan>[
                                          TextSpan(
                                              text: '${r.uname}：',
                                              style: const TextStyle(
                                                  color: AppColors.blue)),
                                          TextSpan(text: r.message),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
