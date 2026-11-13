import 'package:flutter/material.dart';

import '../../core/navigation.dart';
import '../../core/partitions.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass.dart';
import '../../widgets/page_header_card.dart';
import '../../widgets/partition_sheet.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import 'home_controller.dart';

/// 首页视图：推荐 / 热门 / 排行榜三个频道。
///
/// 数据与分页逻辑在 [HomeController] 里，这里只负责画。
class HomeView extends StatefulWidget {
  const HomeView({Key? key}) : super(key: key);

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  late final HomeController _controller;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _controller = HomeController();
    _tabController = TabController(length: HomeChannel.values.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.load(HomeChannel.recommended);
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final channel = HomeChannel.values[_tabController.index];
    if (channel != _controller.channel) {
      _controller.selectChannel(channel);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 注意：AnimatedBuilder **只包 body**，不包整个 Scaffold。
    // 整页重建会让 AppBar 的 flexibleSpace（玻璃条）与卡片表面的高光
    // 动画反复重播，表现为整页蒙一层白纱、标题被盖住。
    // AppBar 保持静态，只把会变的「数据源」小部件单独订阅。
    return Scaffold(
      appBar: AppBar(
            titleSpacing: 16,
            flexibleSpace: const GlassBar(),
            title: Row(
              children: const <Widget>[
                AppLogo(size: 28),
                SizedBox(width: 9),
                Text('Bili Lite'),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => SourceBadge(
                      source: _controller.sourceOf(_controller.channel)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GlassPill(
                  radius: 12,
                  padding: const EdgeInsets.all(7),
                  onTap: () =>
                      _controller.load(_controller.channel, force: true),
                  child: const Icon(Icons.refresh_rounded,
                      size: 18, color: AppColors.pink),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: false,
              indicator: GlassDecorations.tabIndicator(context),
              indicatorPadding: GlassDecorations.tabIndicatorPadding,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: GlassDecorations.tabLabelColor(context),
              unselectedLabelColor:
                  GlassDecorations.tabUnselectedLabelColor(context),
              labelStyle:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _buildBody(_controller.channel),
      ),
    );
  }

  Widget _buildBody(HomeChannel channel) {
    final videos = _controller.videosOf(channel);
    final error = _controller.errorOf(channel);
    final style = prefs.cardStyle;

    if (_controller.loadingOf(channel) && videos.isEmpty && error == null) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(
          columns: Breakpoints.columns(c.maxWidth),
          style: style,
        );
      });
    }
    if (error != null && videos.isEmpty) {
      return ErrorView(
        message: error,
        onRetry: () => _controller.load(channel, force: true),
      );
    }

    return VideoGrid(
      videos: videos,
      ranked: channel == HomeChannel.rank,
      hasMore: _controller.hasMore(channel),
      loadingMore: _controller.loadingMore,
      style: style,
      onLoadMore: () => _controller.load(channel, more: true),
      onRefresh: () => _controller.load(channel, force: true),
      onTap: (Video video) => openVideoDetail(context, video),
      header: _buildHeader(channel),
      empty: EmptyView(
        icon: Icons.video_library_outlined,
        title: '这里还没有内容',
        subtitle: '下拉刷新试试，或确认 BFF 服务已启动',
        action: GlassChip(
          label: '刷新',
          icon: Icons.refresh_rounded,
          tint: AppColors.pink,
          onTap: () => _controller.load(channel, force: true),
        ),
      ),
    );
  }

  Widget _buildHeader(HomeChannel channel) {
    const titles = <String>['为你推荐', '综合热门', '全站排行榜'];
    const notes = <String>[
      '实时拉取 B 站公开推荐流，下拉可换一批',
      '按综合热度排序的近期热门稿件',
      '根据内容质量与近期数据综合展示',
    ];

    return PageHeaderCard(
      title: channel == HomeChannel.rank && _controller.rid != 0
          ? '${BiliPartitions.nameOf(_controller.rid)}排行榜'
          : titles[channel.index],
      count: '共 ${_controller.videosOf(channel).length} 条',
      subtitle: channel == HomeChannel.rank && _controller.rankNote.isNotEmpty
          ? _controller.rankNote
          : notes[channel.index],
      // 排行榜频道额外给一个「分区」浮层入口：21 个分区挤在横条里
      // 一眼扫不完，浮层是图标 + 名称的网格，识别度高得多。
      trailing: channel == HomeChannel.rank
          ? GlassChip(
              label: '分区',
              icon: Icons.grid_view_rounded,
              tint: AppColors.pink,
              radius: 12,
              onTap: () => _openPartitionPicker(),
            )
          : null,
      subtitleWidget:
          channel == HomeChannel.rank ? _partitionBar() : null,
    );
  }

  Future<void> _openPartitionPicker() async {
    await showPartitionPicker(
      context,
      selectedRid: _controller.rid,
      onSelected: (rid) => _controller.changePartition(rid),
    );
  }

  /// 排行榜频道的分区横条（与浮层双通道：横条快，浮层全）。
  Widget _partitionBar() {
    final sub = context.subTextColor;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: appState.partitions.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final p = appState.partitions[index];
          final selected = p.rid == _controller.rid;
          return GlassChip(
            label: p.name,
            selected: selected,
            radius: 16,
            tint: AppColors.pink,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            labelStyle: TextStyle(
                fontSize: AppFontSize.body,
                color: selected ? AppColors.pink : sub,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            onTap: () => _controller.changePartition(p.rid),
          );
        },
      ),
    );
  }
}
