import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import '../detail/detail_page.dart';

/// 首页：推荐 / 热门 / 排行榜三个频道，各自缓存数据与分页游标。
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  int _activeTab = 0;
  final Map<int, List<Video>> _videos = <int, List<Video>>{
    0: <Video>[],
    1: <Video>[],
    2: <Video>[],
  };
  final Map<int, String> _sources = <int, String>{};
  final Map<int, String?> _errors = <int, String?>{};
  final Map<int, bool> _loading = <int, bool>{};

  int _freshIdx = 1;
  int _popularPage = 1;
  int _rid = 0;
  String _rankNote = '';
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final i = _tabController.index;
        if (i != _activeTab) {
          setState(() => _activeTab = i);
          _load(i);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(0));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Video> _merge(List<Video> base, List<Video> incoming) {
    final seen = base.map((e) => e.bvid).toSet();
    final result = List<Video>.from(base);
    for (final v in incoming) {
      if (v.bvid.isNotEmpty && seen.add(v.bvid)) result.add(v);
    }
    return result;
  }

  Future<void> _load(int tab, {bool more = false, bool force = false}) async {
    if (_loading[tab] == true) return;
    if (!more && !force && _videos[tab]!.isNotEmpty) return;

    if (more) _isLoadingMore = true;
    setState(() => _loading[tab] = true);

    try {
      if (tab == 0) {
        if (more) {
          _freshIdx += 1;
        } else if (force) {
          _freshIdx = 1;
        }
        final res = await repo.feed(ps: 20, freshIdx: _freshIdx);
        setState(() {
          _videos[0] = more ? _merge(_videos[0]!, res.data) : res.data;
          _sources[0] = res.source;
          _errors[0] = null;
        });
      } else if (tab == 1) {
        if (more) {
          _popularPage += 1;
        } else if (force) {
          _popularPage = 1;
        }
        final res = await repo.popular(pn: _popularPage, ps: 20);
        setState(() {
          _videos[1] = more ? _merge(_videos[1]!, res.data) : res.data;
          _sources[1] = res.source;
          _errors[1] = null;
        });
      } else {
        final res = await repo.rank(rid: _rid);
        setState(() {
          _videos[2] = res.data.list;
          _rankNote = res.data.note;
          _sources[2] = res.source;
          _errors[2] = null;
        });
      }
    } catch (e) {
      setState(() => _errors[tab] = e.toString());
    } finally {
      _isLoadingMore = false;
      if (mounted) setState(() => _loading[tab] = false);
    }
  }

  void _changePartition(int rid) {
    if (_rid == rid) return;
    _rid = rid;
    _load(2, force: true);
  }

  void _openDetail(Video video) {
    library.addHistory(video);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoDetailPage(video: video)),
    );
  }

  bool _hasMore(int tab) {
    if (tab == 0) return true;
    if (tab == 1) return _popularPage < 10;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        flexibleSpace: const GlassBar(),
        title: Row(
          children: const <Widget>[
            _GlassLogo(),
            SizedBox(width: 9),
            Text('Bili Lite'),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SourceBadge(source: _sources[_activeTab] ?? ''),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GlassPill(
              radius: 12,
              padding: const EdgeInsets.all(7),
              onTap: () => _load(_activeTab, force: true),
              child: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.pink),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicator: GlassDecorations.tabIndicator(context),
          indicatorPadding: GlassDecorations.tabIndicatorPadding,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: GlassDecorations.tabLabelColor(context),
          unselectedLabelColor: GlassDecorations.tabUnselectedLabelColor(context),
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          labelPadding: const EdgeInsets.symmetric(horizontal: 18),
          tabs: const <Widget>[
            Tab(text: '推荐'),
            Tab(text: '热门'),
            Tab(text: '排行榜'),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final tab = _activeTab;
    final videos = _videos[tab]!;
    final error = _errors[tab];

    if (_loading[tab] == true && videos.isEmpty && error == null) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(columns: Breakpoints.columns(c.maxWidth));
      });
    }
    if (error != null && videos.isEmpty) {
      return ErrorView(message: error, onRetry: () => _load(tab, force: true));
    }

    return VideoGrid(
      videos: videos,
      ranked: tab == 2,
      hasMore: _hasMore(tab),
      loadingMore: _isLoadingMore,
      onLoadMore: () => _load(tab, more: true),
      onRefresh: () => _load(tab, force: true),
      onTap: _openDetail,
      header: _buildHeader(tab),
      empty: EmptyView(
        icon: Icons.video_library_outlined,
        title: '这里还没有内容',
        subtitle: '下拉刷新试试，或确认 BFF 服务已启动',
        action: GlassChip(
          label: '刷新',
          icon: Icons.refresh_rounded,
          tint: AppColors.pink,
          onTap: () => _load(tab, force: true),
        ),
      ),
    );
  }

  Widget _buildHeader(int tab) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    final titles = <String>['为你推荐', '综合热门', '全站排行榜'];
    final notes = <String>[
      '实时拉取 B 站公开推荐流，下拉可换一批',
      '按综合热度排序的近期热门稿件',
      _rankNote.isNotEmpty ? _rankNote : '根据内容质量与近期数据综合展示',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  tab == 2 && _rid != 0
                      ? '${_partitionName(_rid)}排行榜'
                      : titles[tab],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text('共 ${_videos[tab]!.length} 条',
                  style: TextStyle(fontSize: 11, color: sub)),
            ],
          ),
          const SizedBox(height: 4),
          Text(notes[tab], style: TextStyle(fontSize: 11.5, color: sub)),
          if (tab == 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: appState.partitions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final p = appState.partitions[index];
                  final selected = p.rid == _rid;
                  return GlassChip(
                    label: p.name,
                    selected: selected,
                    radius: 16,
                    tint: AppColors.pink,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: selected ? AppColors.pink : sub,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500),
                    onTap: () => _changePartition(p.rid),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
        ),
      ),
    );
  }

  String _partitionName(int rid) {
    for (final p in appState.partitions) {
      if (p.rid == rid) return p.name;
    }
    return '分区';
  }
}

class _GlassLogo extends StatelessWidget {
  const _GlassLogo();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 9,
      padding: EdgeInsets.zero,
      tint: AppColors.pink,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text('bi',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8)),
        ),
      ),
    );
  }
}
