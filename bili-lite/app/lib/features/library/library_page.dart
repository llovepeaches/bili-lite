import 'package:flutter/material.dart';

import '../../core/navigation.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/glass.dart';
import '../../widgets/page_header_card.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';

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
    openVideoDetail(context, video);
  }

  Future<void> _confirmClear(LibraryKind kind) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空列表？',
      message: '将删除${_tabLabels[LibraryKind.values.indexOf(kind)]}中的全部 '
          '${library.count(kind)} 条记录，此操作不可撤销。',
      confirmLabel: '清空',
    );
    if (ok) await library.clear(kind);
  }

  Future<void> _confirmRemove(LibraryKind kind, Video video) async {
    final ok = await showConfirmDialog(
      context,
      title: '移除这条记录？',
      message: video.title,
      confirmLabel: '移除',
    );
    if (ok) await library.remove(kind, video.bvid);
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
      header: PageHeaderCard(
        title: _tabTitles[_active],
        count: '${videos.length} 条',
        subtitle: _tabHints[_active],
        trailing: videos.isEmpty
            ? null
            : GlassChip(
                label: '清空',
                icon: Icons.delete_outline_rounded,
                tint: AppColors.pink,
                radius: 12,
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                labelStyle:
                    const TextStyle(fontSize: 12, color: AppColors.pink),
                onTap: () => _confirmClear(kind),
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
