import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import '../detail/detail_page.dart';

const List<String> _tabLabels = <String>['收藏', '历史', '稍后再看'];
const List<IconData> _tabIcons = <IconData>[
  Icons.favorite_border_rounded,
  Icons.history_rounded,
  Icons.watch_later_outlined,
];
const List<String> _tabTitles = <String>[
  '收藏的视频',
  '观看历史',
  '稍后再看',
];
const List<String> _tabHints = <String>[
  '长按卡片可移除，数据仅保存在本机',
  '自动记录打开过的视频，最多保留 200 条',
  '想看但暂时没空？先存到这里',
];

class LibraryPage extends StatefulWidget {
  const LibraryPage({Key? key}) : super(key: key);

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index != _active) {
        setState(() => _active = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  LibraryKind get _kind => LibraryKind.values[_active];

  void _openDetail(Video video) {
    library.addHistory(video);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoDetailPage(video: video)),
    );
  }

  Future<void> _confirmClear(LibraryKind kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空列表？'),
        content: Text('将删除${_tabLabels[LibraryKind.values.indexOf(kind)]}中的全部 '
            '${library.count(kind)} 条记录，此操作不可撤销。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(primary: AppColors.pink),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) await library.clear(kind);
  }

  Future<void> _confirmRemove(LibraryKind kind, Video video) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除这条记录？'),
        content: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(primary: AppColors.pink),
              child: const Text('移除')),
        ],
      ),
    );
    if (ok == true) await library.remove(kind, video.bvid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        flexibleSpace: const GlassBar(),
        bottom: TabBar(
          controller: _tabController,
          indicator: GlassDecorations.tabIndicator(context),
          indicatorPadding: GlassDecorations.tabIndicatorPadding,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: GlassDecorations.tabLabelColor(context),
          unselectedLabelColor: GlassDecorations.tabUnselectedLabelColor(context),
          labelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          tabs: List<Widget>.generate(
            _tabLabels.length,
            (i) => Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_tabIcons[i], size: 15),
                  const SizedBox(width: 5),
                  Text(_tabLabels[i], style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: library,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final kind = _kind;
    final items = library.of(kind);
    final videos = items.map((e) => e.video).toList();

    if (!library.loaded) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(columns: Breakpoints.columns(c.maxWidth));
      });
    }

    return VideoGrid(
      videos: videos,
      onRefresh: () => library.load(),
      onTap: _openDetail,
      onLongPress: (video) => _confirmRemove(kind, video),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_tabTitles[_active],
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${videos.length} 条',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.lightSub)),
                const Spacer(),
                if (videos.isNotEmpty)
                  GlassChip(
                    label: '清空',
                    icon: Icons.delete_outline_rounded,
                    tint: AppColors.pink,
                    radius: 12,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    labelStyle: const TextStyle(fontSize: 12, color: AppColors.pink),
                    onTap: () => _confirmClear(kind),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(_tabHints[_active],
                style: const TextStyle(fontSize: 11.5, color: AppColors.lightSub)),
            const SizedBox(height: 6),
          ],
        ),
        ),
      ),
      empty: EmptyView(
        icon: _tabIcons[_active],
        title: '${_tabTitles[_active]}还是空的',
        subtitle: _active == 0
            ? '打开任意视频，点右上角的收藏按钮即可加入'
            : _active == 1
                ? '浏览过的视频会自动出现在这里'
                : '在视频详情页点「稍后再看」即可加入',
      ),
    );
  }
}
