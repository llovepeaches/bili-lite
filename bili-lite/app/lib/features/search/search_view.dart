import 'package:flutter/material.dart';

import '../../core/navigation.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import 'search_controller.dart';

/// 搜索页视图。逻辑与状态在 [SearchController] 里。
///
/// 落地页只保留搜索历史与简短空状态。原先的「大家都在搜」是一组写死在
/// 客户端的推荐词，既不来自 B 站实时热搜，也无差别推给所有用户，容易被
/// 误认成真实榜单；移除后搜索页不再编造内容，历史与空状态保持原样。
class SearchView extends StatefulWidget {
  const SearchView({Key? key}) : super(key: key);

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _input = TextEditingController();
  late final SearchController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SearchController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  /// 统一的搜索入口：跑请求 → 把关键词回填到输入框 → 刷新清除按钮。
  Future<void> _search(String word, {bool more = false}) async {
    await _controller.search(word, more: more);
    if (!mounted) return;
    final keyword = _controller.keyword;
    if (!more && _input.text != keyword) {
      _input.text = keyword;
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    }
    if (mounted) setState(() {});
  }

  void _clear() {
    _input.clear();
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        flexibleSpace: const GlassBar(),
        title: SizedBox(
          height: 40,
          child: GlassPanel(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _search(v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索视频、UP 主…',
                prefixIcon: Icon(Icons.search_rounded,
                    size: 19, color: dark ? AppColors.darkSub : AppColors.lightSub),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, maxHeight: 36),
                suffixIcon: _input.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(maxWidth: 34, maxHeight: 34),
                        onPressed: _clear,
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 2),
            child: GlassChip(
              label: '搜索',
              tint: AppColors.pink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              labelStyle: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700),
              onTap: () => _search(_input.text),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final sub = context.subTextColor;
    final keyword = _controller.keyword;
    if (keyword.isEmpty) return _buildLanding();

    final results = _controller.results;
    final error = _controller.error;

    if (_controller.loading && results.isEmpty && error == null) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(
          columns: Breakpoints.columns(c.maxWidth),
          style: prefs.cardStyle,
        );
      });
    }
    if (error != null && results.isEmpty) {
      return ErrorView(message: error, onRetry: () => _search(keyword));
    }

    return VideoGrid(
      videos: results,
      style: prefs.cardStyle,
      onRefresh: () => _search(keyword),
      onTap: (Video video) => openVideoDetail(context, video),
      hasMore: _controller.hasMore,
      loadingMore: _controller.loadingMore,
      onLoadMore: () => _search(keyword, more: true),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: GlassPanel(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text('「$keyword」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text('约 ${_controller.total} 条结果',
                  style: TextStyle(fontSize: AppFontSize.caption, color: sub)),
              const SizedBox(width: 8),
              SourceBadge(source: _controller.source),
            ],
          ),
        ),
      ),
      empty: EmptyView(
        icon: Icons.search_off_rounded,
        title: '没有找到相关视频',
        subtitle: '换个关键词试试，或检查服务连接',
      ),
    );
  }

  Widget _buildLanding() {
    final sub = context.subTextColor;
    // 订阅 searchHistory：历史在别处（如设置页清空本地数据）变化时，这里同步刷新。
    return AnimatedBuilder(
      animation: searchHistory,
      builder: (context, _) {
        final history = searchHistory.items;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: <Widget>[
            if (history.isNotEmpty) ...<Widget>[
              SectionTitle(
                title: '搜索历史',
                trailing: GlassPill(
                  radius: 10,
                  padding: const EdgeInsets.all(6),
                  onTap: () => searchHistory.clear(),
                  child: Icon(Icons.delete_outline_rounded, size: 17, color: sub),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: history
                    .map((word) => GlassChip(
                          label: word,
                          radius: 12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          labelStyle: TextStyle(fontSize: 12, color: sub),
                          onTap: () => _search(word),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 26),
            ],
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: <Widget>[
                  Icon(Icons.travel_explore_outlined,
                      size: 40, color: sub.withOpacity(0.5)),
                  const SizedBox(height: 10),
                  Text('只搜视频，不打扰',
                      style: TextStyle(fontSize: 12.5, color: sub)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
