import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';
import '../account/login_gate.dart';
import 'space_filter.dart';

/// 应用内 UP 主空间。
///
/// 「查看主页」原先直接 `launchUrl` 跳系统浏览器，用户一点击就离开 App。
/// 现在改成命名路由在应用内打开：先展示 UP 主资料，再列出检索到的该 UP 主
/// 稿件，点击任一稿件走 `openVideoDetail` 留在应用内。
///
/// 数据边界（不编造内容）：B 站的空间投稿接口对匿名请求返回 -403 / 风控 HTML，
/// 所以这里复用已经验证可用的站内搜索接口按 UP 主名称检索，再按 mid 过滤，
/// 只展示确实属于该 UP 主的稿件；检索不到就如实显示空态。
class SpaceView extends StatefulWidget {
  const SpaceView({Key? key, required this.owner}) : super(key: key);

  final Owner owner;

  @override
  State<SpaceView> createState() => _SpaceViewState();
}

class _SpaceViewState extends State<SpaceView> {
  bool _loading = true;
  String? _error;
  List<Video> _videos = <Video>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = widget.owner.name.trim();
      if (name.isEmpty) throw StateError('缺少 UP 主名称');
      final res = await repo.search(name);
      // 搜索结果可能混入同名 / 转载稿件，只保留 mid 一致的。
      final mine = filterOwnerVideos(res.data.list, widget.owner.mid);
      if (!mounted) return;
      setState(() {
        _videos = mine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.owner.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        flexibleSpace: const GlassBar(),
      ),
      body: RefreshIndicator(
        color: AppColors.pink,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            _ownerCard(context),
            const SizedBox(height: 12),
            const LoginRequiredHint(feature: 'UP 主完整稿件与评论'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              _notice(context, '稿件加载失败，下拉可重试', onRetry: _load)
            else if (_videos.isEmpty)
              _notice(context, '暂未检索到该 UP 主的稿件', onRetry: _load)
            else ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  '稿件 · ${_videos.length}',
                  style: TextStyle(
                      fontSize: 12,
                      color: context.subTextColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
              ..._videos.map((Video v) => _videoRow(context, v)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ownerCard(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          UserAvatar(
              url: widget.owner.face, name: widget.owner.name, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('UID ${widget.owner.mid}',
                    style: TextStyle(fontSize: 11.5, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoRow(BuildContext context, Video v) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.all(10),
        onTap: () => openVideoDetail(context, v),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 132,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CoverImage(url: v.cover, radius: 10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    v.title.isEmpty ? '（无标题）' : v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Fmt.compact(v.stat.view)} 播放 · ${v.durationText}',
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, String message,
      {required Future<void> Function() onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.subTextColor)),
            const SizedBox(height: 12),
            GlassChip(
              label: '重试',
              icon: Icons.refresh_rounded,
              tint: AppColors.pink,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
