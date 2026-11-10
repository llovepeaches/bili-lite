import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import '../../widgets/video_grid.dart';
import '../detail/detail_page.dart';

const List<String> _hotWords = <String>[
  'Flutter 教程',
  '崩坏：星穹铁道',
  '科技数码',
  '纪录片',
  '编程入门',
  '美食',
  '音乐现场',
  '动画短片',
];

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const String _historyKey = 'bili_lite_search_history';

  final TextEditingController _input = TextEditingController();

  String _keyword = '';
  List<Video> _results = <Video>[];
  int _page = 1;
  int _pages = 0;
  int _total = 0;
  String _source = '';
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;
  List<String> _history = <String>[];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        _history = (json.decode(raw) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveHistory(String word) async {
    _history.remove(word);
    _history.insert(0, word);
    if (_history.length > 10) _history = _history.sublist(0, 10);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyKey, json.encode(_history));
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    _history = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _search(String word, {bool more = false}) async {
    final keyword = word.trim();
    if (keyword.isEmpty || _loading) return;

    if (more) {
      if (_loadingMore || _page >= _pages) return;
      _loadingMore = true;
      _page += 1;
    } else {
      _page = 1;
      _results = <Video>[];
      _error = null;
      _keyword = keyword;
      _input.text = keyword;
      await _saveHistory(keyword);
    }

    setState(() => _loading = true);
    try {
      final res = await repo.search(keyword, page: _page);
      if (!mounted) return;
      final seen = _results.map((e) => e.bvid).toSet();
      final added = <Video>[];
      for (final v in res.data.list) {
        if (seen.add(v.bvid)) added.add(v);
      }
      setState(() {
        _results = more ? <Video>[..._results, ...added] : added;
        _pages = res.data.pages;
        _total = res.data.total;
        _source = res.source;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loadingMore = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear() {
    _input.clear();
    setState(() {
      _keyword = '';
      _results = <Video>[];
      _error = null;
      _source = '';
    });
  }

  void _openDetail(Video video) {
    library.addHistory(video);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoDetailPage(video: video)),
    );
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_keyword.isEmpty) return _buildLanding();

    if (_loading && _results.isEmpty && _error == null) {
      return LayoutBuilder(builder: (context, c) {
        return LoadingGrid(columns: Breakpoints.columns(c.maxWidth));
      });
    }
    if (_error != null && _results.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _search(_keyword));
    }

    return VideoGrid(
      videos: _results,
      onRefresh: () => _search(_keyword),
      onTap: _openDetail,
      hasMore: _page < _pages,
      loadingMore: _loadingMore,
      onLoadMore: () => _search(_keyword, more: true),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: GlassPanel(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text('「$_keyword」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text('约 $_total 条结果',
                  style: const TextStyle(fontSize: 11, color: AppColors.lightSub)),
              const SizedBox(width: 8),
              SourceBadge(source: _source),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        if (_history.isNotEmpty) ...[
          SectionTitle(
            title: '搜索历史',
            trailing: GlassPill(
              radius: 10,
              padding: const EdgeInsets.all(6),
              onTap: _clearHistory,
              child: Icon(Icons.delete_outline_rounded, size: 17, color: sub),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history
                .map((word) => GlassChip(
                      label: word,
                      radius: 12,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      labelStyle: TextStyle(fontSize: 12, color: sub),
                      onTap: () => _search(word),
                    ))
                .toList(),
          ),
          const SizedBox(height: 26),
        ],
        const SectionTitle(title: '大家都在搜'),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: _hotWords.asMap().entries.map((entry) {
            final index = entry.key;
            final word = entry.value;
            return GlassChip(
              leading: index < 3
                  ? Container(
                      width: 17,
                      height: 17,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              AppColors.pink.withOpacity(index == 0 ? 1 : 0.85),
                              AppColors.pink.withOpacity(index == 0 ? 0.8 : 0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white54, width: 0.7),
                      ),
                      child: Text('${index + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    )
                  : null,
              label: word,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              labelStyle: const TextStyle(fontSize: 12.5),
              onTap: () => _search(word),
            );
          }).toList(),
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(Icons.travel_explore_outlined, size: 40, color: sub.withOpacity(0.5)),
              const SizedBox(height: 10),
              Text('只搜视频，不打扰',
                  style: TextStyle(fontSize: 12.5, color: sub)),
            ],
          ),
        ),
      ],
    );
  }
}
