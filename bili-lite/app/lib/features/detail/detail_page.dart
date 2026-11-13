import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import '../player/player_page.dart';

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({Key? key, required this.video}) : super(key: key);

  final Video video;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  VideoDetail? _detail;
  final List<Comment> _comments = <Comment>[];
  int _commentCount = 0;
  int _pn = 1;
  int _sort = 2;

  bool _loadingComments = false;
  bool _loadingMore = false;
  bool _descExpanded = false;

  String? _detailError;
  String? _commentError;
  String _source = '';

  Video get _video => _detail?.video ?? widget.video;
  String get _aid => _video.aid.isNotEmpty ? _video.aid : widget.video.aid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDetail();
      _loadComments(refresh: true);
    });
  }

  Future<void> _loadDetail() async {
    try {
      final res = await repo.video(widget.video.bvid, aid: widget.video.aid);
      if (!mounted) return;
      setState(() {
        _detail = res.data;
        _source = res.source;
        _detailError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _detailError = e.toString());
    }
  }

  Future<void> _loadComments({bool refresh = false, bool more = false}) async {
    if (_loadingComments || _aid.isEmpty) return;
    if (more) {
      _loadingMore = true;
      _pn += 1;
    } else if (refresh) {
      _pn = 1;
      _comments.clear();
    }
    setState(() => _loadingComments = true);
    try {
      final res = await repo.reply(_aid, pn: _pn, ps: 20, sort: _sort);
      if (!mounted) return;
      setState(() {
        _comments.addAll(res.data.list);
        _commentCount = res.data.count;
        _commentError = null;
      });
    } catch (e) {
      // 重构前加载更多失败时 _pn 没有回退，用户点「重试」会跳过一页评论。
      if (more) _pn -= 1;
      if (mounted) setState(() => _commentError = e.toString());
    } finally {
      _loadingMore = false;
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  void _changeSort(int sort) {
    if (_sort == sort) return;
    _sort = sort;
    _loadComments(refresh: true);
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// 应用内播放：打开官方外链播放器，不离开当前应用。
  void _openPlayer() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerPage(video: _video),
    ));
  }

  /// 需要账号的互动（评论 / 投币 / 点赞）统一回官方客户端完成。
  Future<void> _openOriginal() async {
    final url = _video.webUrl;
    final uri = Uri.parse(url);
    try {
      final ok = await canLaunchUrl(uri)
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: url));
        _notify('已复制原视频链接，可粘贴到浏览器打开');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _notify('已复制原视频链接，可粘贴到浏览器打开');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频详情', style: TextStyle(fontSize: 17)),
        flexibleSpace: const GlassBar(),
        actions: <Widget>[
          AnimatedBuilder(
            animation: library,
            builder: (_, __) => _GlassIconAction(
              tooltip: library.isFavorite(widget.video.bvid) ? '取消收藏' : '收藏',
              icon: library.isFavorite(widget.video.bvid)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              active: library.isFavorite(widget.video.bvid),
              onTap: () => library.toggle(LibraryKind.favorites, _video),
            ),
          ),
          AnimatedBuilder(
            animation: library,
            builder: (_, __) => _GlassIconAction(
              tooltip: library.inWatchLater(widget.video.bvid)
                  ? '移出稍后再看'
                  : '稍后再看',
              icon: library.inWatchLater(widget.video.bvid)
                  ? Icons.watch_later_rounded
                  : Icons.watch_later_outlined,
              active: library.inWatchLater(widget.video.bvid),
              onTap: () => library.toggle(LibraryKind.watchLater, _video),
            ),
          ),
          _GlassIconAction(
            tooltip: '应用内播放',
            icon: Icons.play_circle_outline_rounded,
            onTap: _openPlayer,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final twoColumn = Breakpoints.detailTwoColumn(constraints.maxWidth);
        if (twoColumn) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildMain(),
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMain(),
              const SizedBox(height: 22),
              const GlassDivider(),
              const SizedBox(height: 14),
              _buildComments(),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildMain() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    final v = _video;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面 + 播放入口
        AspectRatio(
          aspectRatio: 16 / 9,
          child: GestureDetector(
            onTap: _openPlayer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(url: v.cover, radius: 14),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.35),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: GlassCircleButton(
                    icon: Icons.play_arrow_rounded,
                    size: 58,
                    onTap: _openPlayer,
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
        ),
        const SizedBox(height: 16),

        // 标题
        Text(
          v.title.isEmpty ? '（无标题）' : v.title,
          style: const TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),

        // 数据行
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Stat(Icons.play_circle_outline, v.stat.view, '播放'),
            _Stat(Icons.subtitles_outlined, v.stat.danmaku, '弹幕'),
            _Stat(Icons.mode_comment_outlined, v.stat.reply, '评论'),
            _Stat(Icons.thumb_up_outlined, v.stat.like, '点赞'),
            _Stat(Icons.monetization_on_outlined, v.stat.coin, '投币'),
            _Stat(Icons.star_border_rounded, v.stat.favorite, '收藏'),
            _Stat(Icons.share_outlined, v.stat.share, '分享'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.schedule_outlined, size: 13, color: sub),
            const SizedBox(width: 4),
            Text(Fmt.relative(v.pubdate), style: TextStyle(fontSize: 12, color: sub)),
            if (v.tname.isNotEmpty) ...[
              const SizedBox(width: 12),
              Icon(Icons.category_outlined, size: 13, color: sub),
              const SizedBox(width: 4),
              Text(v.tname, style: TextStyle(fontSize: 12, color: sub)),
            ],
            const Spacer(),
            SourceBadge(source: _source),
          ],
        ),
        const SizedBox(height: 16),

        // UP 主
        GlassPanel(
          radius: 16,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(url: v.owner.face, name: v.owner.name, size: 40),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.owner.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('UID ${v.owner.mid}',
                        style: TextStyle(fontSize: 11, color: sub)),
                  ],
                ),
              ),
              Text('UP 主',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.pink,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 简介
        if (v.desc.isNotEmpty) ...[
          const SectionTitle(title: '简介'),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Text(
              v.desc,
              maxLines: _descExpanded ? 100 : 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.6, color: sub),
            ),
          ),
          const SizedBox(height: 8),
          GlassPill(
            radius: 9,
            tint: AppColors.pink.withOpacity(0.16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Text(_descExpanded ? '收起' : '展开全部',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.pink,
                    fontWeight: FontWeight.w600)),
          ),
        ],

        // 分 P
        if ((_detail?.pages.length ?? 0) > 1) ...[
          const SizedBox(height: 8),
          SectionTitle(
              title: '分 P · ${_detail!.pages.length}',
              trailing: Text('共 ${_detail!.pages.length} 集',
                  style: TextStyle(fontSize: 11, color: sub))),
          ..._detail!.pages.map((p) => ListTile(
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

        const SizedBox(height: 16),
        // 操作区
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AnimatedBuilder(
              animation: library,
              builder: (_, __) => _ActionButton(
                icon: library.isFavorite(widget.video.bvid)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: library.isFavorite(widget.video.bvid) ? '已收藏' : '收藏',
                active: library.isFavorite(widget.video.bvid),
                onTap: () => library.toggle(LibraryKind.favorites, _video),
              ),
            ),
            AnimatedBuilder(
              animation: library,
              builder: (_, __) => _ActionButton(
                icon: library.inWatchLater(widget.video.bvid)
                    ? Icons.watch_later_rounded
                    : Icons.watch_later_outlined,
                label: library.inWatchLater(widget.video.bvid) ? '已添加' : '稍后再看',
                active: library.inWatchLater(widget.video.bvid),
                onTap: () => library.toggle(LibraryKind.watchLater, _video),
              ),
            ),
            _ActionButton(
              icon: Icons.mode_comment_outlined,
              label: '评论 / 投币',
              onTap: _openOriginal,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '点击封面在应用内通过 B 站官方外链播放器观看；评论、投币、点赞等观看侧互动'
          '请在官方客户端完成——开放平台没有对应 scope，本应用不会用 OAuth 凭证调用写接口。',
          style: TextStyle(fontSize: 11, color: sub, height: 1.5),
        ),
        if (_detailError != null) ...[
          const SizedBox(height: 10),
          Text('详情补充失败：$_detailError',
              style: TextStyle(fontSize: 11, color: Colors.orange)),
        ],
      ],
    );
  }

  Widget _buildComments() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: <Widget>[
            const GlassAccent(),
            const SizedBox(width: 8),
            const Text('评论',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(_commentCount > 0 ? Fmt.compact(_commentCount) : '',
                style: TextStyle(fontSize: 12, color: sub)),
            const Spacer(),
            _SortChip(label: '热门', value: 2, current: _sort, onTap: _changeSort),
            const SizedBox(width: 6),
            _SortChip(label: '最新', value: 0, current: _sort, onTap: _changeSort),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingComments && _comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_commentError != null && _comments.isEmpty)
          ErrorView(message: _commentError!, onRetry: () => _loadComments(refresh: true), compact: true)
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
                child: Text('暂时没有评论', style: TextStyle(fontSize: 12.5, color: sub))),
          )
        else
          Column(
            children: _comments.map((c) => _CommentCard(comment: c)).toList(),
          ),
        if (_comments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: _loadingMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : GlassChip(
                    label: '加载更多评论',
                    icon: Icons.expand_more_rounded,
                    tint: AppColors.pink,
                    radius: 12,
                    onTap: () => _loadComments(more: true),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '第三方访客身份下，B 站通常只开放部分热评。',
              style: TextStyle(fontSize: 10.5, color: sub),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: sub),
          const SizedBox(width: 3),
          Text(Fmt.compact(value), style: TextStyle(fontSize: 11.5, color: sub)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      label: label,
      icon: icon,
      selected: active,
      tint: AppColors.pink,
      radius: 13,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      labelStyle: const TextStyle(fontSize: 12.5),
      onTap: onTap,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.all(12),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(url: comment.avatar, name: comment.uname, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(comment.uname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.pink)),
                    ),
                    if (comment.isTop) ...[
                      const SizedBox(width: 6),
                      GlassPill(
                        radius: 4,
                        tint: AppColors.pink.withOpacity(0.18),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                  children: [
                    Icon(Icons.thumb_up_off_alt_outlined, size: 12, color: sub),
                    const SizedBox(width: 3),
                    Text(Fmt.compact(comment.like),
                        style: TextStyle(fontSize: 10.5, color: sub)),
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: 14),
                      Text('${Fmt.compact(comment.replyCount)} 条回复',
                          style: TextStyle(fontSize: 10.5, color: sub)),
                    ],
                    if (comment.location.isNotEmpty) ...[
                      const Spacer(),
                      Text(comment.location,
                          style: TextStyle(fontSize: 10.5, color: sub)),
                    ],
                  ],
                ),
                if (comment.replies.isNotEmpty) ...[
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
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 11.5, color: sub),
                                      children: [
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

/// AppBar 上的圆形玻璃图标按钮。
class _GlassIconAction extends StatelessWidget {
  const _GlassIconAction({
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: GlassPill(
          radius: 13,
          padding: const EdgeInsets.all(8),
          tint: active ? AppColors.pink.withOpacity(0.20) : null,
          onTap: onTap,
          child: Icon(
            icon,
            size: 19,
            color: active
                ? AppColors.pink
                : (dark ? AppColors.darkText : AppColors.lightText),
          ),
        ),
      ),
    );
  }
}
