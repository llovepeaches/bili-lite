import 'package:flutter/material.dart';

import '../../core/navigation.dart';
import '../../core/tokens.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/confirm_dialog.dart';
import '../account/account_entry.dart';
import '../../widgets/glass.dart';
import '../../widgets/page_header_card.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import 'library_controller.dart';

/// 「我的」页（视图层）：收藏 / 观看历史 / 稍后再看。
///
/// 三个 tab 共用一套列表逻辑，元数据与切换状态见 [LibraryController]。
class LibraryPage extends StatefulWidget {
  const LibraryPage({Key? key}) : super(key: key);

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final LibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LibraryController();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _controller.select(_tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openDetail(Video video) {
    openVideoDetail(context, video);
  }

  Future<void> _confirmClear(LibraryKind kind) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空列表？',
      message: '将删除${LibraryController.labels[LibraryKind.values.indexOf(kind)]}中的全部 '
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
            LibraryController.labels.length,
            (i) => Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LibraryController.icons[i], size: 15),
                  const SizedBox(width: 5),
                  Text(LibraryController.labels[i],
                      style: const TextStyle(fontSize: 13)),
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
    final kind = _controller.kind;
    final items = library.of(kind);
    final videos = items.map((e) => e.video).toList();

    if (!library.loaded) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(
          columns: Breakpoints.columns(c.maxWidth),
          style: prefs.cardStyle,
        );
      });
    }

    return VideoGrid(
      videos: videos,
      style: prefs.cardStyle,
      onRefresh: () => library.load(),
      onTap: _openDetail,
      onLongPress: (video) => _confirmRemove(kind, video),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 登录入口前置：账号卡片原本只藏在设置页最底部，
          // 用户在「我的」页看不到，等于没有登录入口。
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: AccountEntry(),
          ),
          PageHeaderCard(
            title: LibraryController.titles[_controller.active],
            count: '${videos.length} 条',
            subtitle: LibraryController.hints[_controller.active],
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
        ],
      ),
      empty: EmptyView(
        icon: LibraryController.icons[_controller.active],
        title: '${LibraryController.titles[_controller.active]}还是空的',
        subtitle: _controller.emptyHint(),
      ),
    );
  }
}
