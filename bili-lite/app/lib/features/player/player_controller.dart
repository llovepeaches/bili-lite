import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../data/bili_direct.dart';
import '../../data/repository.dart';
import '../../state/globals.dart';
import 'danmaku_layout.dart';
import 'video_surface.dart';

/// 应用内播放控制器：管播放地址、弹幕数据与播放状态。
///
/// 职责划分：
///   * [VideoSurface] 只负责「画面 + 播放控制」，平台差异都在它内部；
///   * 这里负责取数据（播放地址 / 弹幕）、算弹幕时间轴、把状态广播给视图。
///
/// 弹幕的绘制分两种：
///   * 原生端：Flutter 画布画在 Texture 之上；
///   * Web 端：画在 DOM canvas 上（见 video_surface_web.dart）。
///   排版公式两边共用 [DanmakuLayout]。
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.bvid,
    required String cid,
    this.quality = 64,
    BiliRepository? repository,
  })  : _repo = repository ?? repo,
        _cid = cid {
    _surface = createVideoSurface(
      onPosition: _handlePosition,
      onDuration: _handleDuration,
      onPlayingChanged: _handlePlaying,
      onError: _handleError,
    );
  }

  final String bvid;

  /// 视频的 cid（分 P id）。播放地址与弹幕都以它为键。
  ///
  /// 列表页的卡片未必带 cid（热门 / 搜索结果里就可能为空），
  /// 所以这里是可变的：加载时若为空会补一次详情再填上。
  late String _cid;

  /// 清晰度码：16=360P、32=480P、64=720P、80=1080P。
  final int quality;

  final BiliRepository _repo;
  late final VideoSurface _surface;

  Timer? _timer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _loading = true;
  bool _danmakuEnabled = true;
  double _danmakuOpacity = 0.9;
  double _danmakuFontScale = 1.0;
  DanmakuArea _danmakuArea = DanmakuArea.full;
  bool _fullscreen = false;
  String? _playError;
  String _qualityLabel = '';
  int _danmakuCount = 0;
  DanmakuSource? _danmaku;

  /// 上一次从底层拿到的真实播放位置与取到它的时刻。
  ///
  /// `video_player` 每 500ms 才回报一次位置，直接拿来驱动弹幕会一顿一顿。
  /// 这里用本地时钟在两次回报之间做线性外推，弹幕就能平滑移动；
  /// 每次拿到新位置时重新校准，误差不会累积。
  Duration _anchorPosition = Duration.zero;
  DateTime _anchorAt = DateTime.now();

  bool _disposed = false;

  // ───────────────────────── 对外状态 ─────────────────────────

  VideoSurface get surface => _surface;

  Duration get position => _position;

  Duration get duration => _duration;

  bool get isPlaying => _playing;

  bool get loading => _loading;

  String? get error => _playError;

  String get qualityLabel => _qualityLabel;

  int get danmakuCount => _danmakuCount;

  bool get danmakuEnabled => _danmakuEnabled;

  double get danmakuOpacity => _danmakuOpacity;

  double get danmakuFontScale => _danmakuFontScale;

  DanmakuArea get danmakuArea => _danmakuArea;

  /// 是否处于全屏横屏页。内嵌播放器据此撤下画面，避免 Web 端同一个
  /// DOM 容器被两处 HtmlElementView 同时挂载。
  bool get fullscreen => _fullscreen;

  DanmakuSource? get danmaku => _danmaku;

  bool get hasVideo => _surface.isReady;

  /// 播放请求头。
  ///
  /// 直连 CDN 时必须带 Referer 与访客身份 Cookie，否则 B 站会 403。
  /// Cookie 由 [BiliDirect] 在启动时通过 spi 换取，和取数据用的是同一份身份。
  static Map<String, String> get playHeaders => <String, String>{
        'Referer': 'https://www.bilibili.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Cookie': BiliDirect.instance.cookieHeader,
      };

  /// BFF 视频流代理地址。
  ///
  /// Web 端必须用它：浏览器的 `<video>` 无法自带 Referer，直连 CDN 必然 403，
  /// 同源代理顺带解决 CORS。
  String get cid => _cid;

  String get streamUrl => ApiConfig.url('/api/stream', <String, String>{
        'bvid': bvid,
        'cid': _cid,
        'qn': '$quality',
      });

  /// 加载播放地址与弹幕。
  Future<void> load() async {
    _loading = true;
    _playError = null;
    _notify();

    // 列表页的卡片不一定带 cid（热门 / 搜索结果里就可能为空），
    // 没有 cid 既拿不到播放地址也拿不到弹幕，先补一次详情。
    if (_cid.isEmpty && bvid.isNotEmpty) {
      try {
        final res = await _repo.video(bvid);
        _cid = res.data.video.cid;
      } catch (_) {
        // 详情失败不致命，下面会如实报「缺少 cid」。
      }
    }

    // 播放地址失败不应该连累弹幕：两个请求并行、各自记录错误。
    await Future.wait<void>(<Future<void>>[_loadPlayUrl(), _loadDanmaku()]);

    _loading = false;
    _notify();
  }

  Future<void> _loadPlayUrl() async {
    try {
      final res = await _repo.playUrl(bvid, _cid, qn: quality);
      _qualityLabel = res.data.qualityLabel;

      // Web 端必须走 BFF 流代理：浏览器的 <video> 无法自带 Referer，
      // 直连 CDN 必然 403；同源代理顺带解决 CORS。
      // 原生端默认直连（不依赖用户电脑上跑着 Node），靠请求头绕过防盗链；
      // 若显式配置了 BFF（ApiConfig.direct == false），也走代理。
      final bool useProxy = !ApiConfig.direct;
      final String url = useProxy ? streamUrl : res.data.url;
      if (url.isEmpty) {
        _playError = '上游未返回可播放地址';
        _notify();
        return;
      }
      await _surface.open(url, headers: playHeaders);
      _playError = null;
      _notify();
    } catch (e) {
      _playError = e.toString();
      _notify();
    }
  }

  Future<void> _loadDanmaku() async {
    if (_cid.isEmpty) return;
    try {
      final res = await _repo.danmaku(_cid);
      final list = res.data.list;
      _danmakuCount = list.length;
      // 必须把当前显示参数带进新建的数据源：弹幕是异步加载的，
      // 用户可能在它回来之前就调过字号 / 区域；不带上会被默认值覆盖。
      _danmaku = DanmakuSource(
        timeline: buildTimeline(list),
        opacity: _danmakuOpacity,
        fontScale: _danmakuFontScale,
        area: _danmakuArea,
      );
      _notify();
    } catch (_) {
      // 弹幕失败不影响播放，静默降级为「无弹幕」。
      _danmakuCount = 0;
      _danmaku = null;
    }
  }

  // ───────────────────────── 播放控制 ─────────────────────────

  Future<void> togglePlay() async {
    if (_playing) {
      await _surface.pause();
    } else {
      await _surface.play();
    }
  }

  Future<void> seek(Duration target) async {
    await _surface.seek(target);
    _anchorPosition = target;
    _anchorAt = DateTime.now();
    _position = target;
    _notify();
  }

  /// 按百分比跳转（进度条拖动）。
  Future<void> seekFraction(double fraction) async {
    final total = _duration.inMilliseconds;
    if (total <= 0) return;
    final target = (total * fraction.clamp(0.0, 1.0)).round();
    await seek(Duration(milliseconds: target));
  }

  void toggleDanmaku() {
    _danmakuEnabled = !_danmakuEnabled;
    _notify();
  }

  void setDanmakuOpacity(double value) {
    _danmakuOpacity = value.clamp(0.1, 1.0);
    _danmaku?.opacity = _danmakuOpacity;
    _notify();
  }

  void setDanmakuFontScale(double value) {
    _danmakuFontScale = value.clamp(0.6, 2.0);
    _danmaku?.fontScale = _danmakuFontScale;
    _notify();
  }

  /// 设置弹幕显示区域（全屏 / 3/4 / 半屏 / 1/4）。
  void setDanmakuArea(DanmakuArea area) {
    _danmakuArea = area;
    _danmaku?.area = area;
    _notify();
  }

  /// 供分段控件直接按下标设置。
  void setDanmakuAreaIndex(int index) =>
      setDanmakuArea(danmakuAreaFromIndex(index));

  /// 进入 / 退出全屏横屏页。视图据此决定谁来渲染 `surface.widget`。
  void setFullscreen(bool value) {
    if (_fullscreen == value) return;
    _fullscreen = value;
    _notify();
  }

  // ───────────────────────── 内部回调 ─────────────────────────

  void _handlePosition(Duration value) {
    _anchorPosition = value;
    _anchorAt = DateTime.now();
    _position = value;
    _notify();
  }

  void _handleDuration(Duration value) {
    _duration = value;
    _notify();
  }

  void _handlePlaying(bool value) {
    _playing = value;
    _notify();
  }

  void _handleError(String? message) {
    _playError = message;
    _notify();
  }

  /// 推进弹幕时间轴。
  void _onTick(Duration _) {
    if (_disposed) return;
    if (!_playing) return;
    final now = DateTime.now();
    final drift = now.difference(_anchorAt).inMilliseconds;
    _position = _anchorPosition + Duration(milliseconds: drift);
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    // Web 端的弹幕必须交给底层（视频是 DOM 元素，Flutter 画布上的弹幕会被挡住）。
    _surface.setDanmaku(_danmakuEnabled ? _danmaku : null);
    notifyListeners();
  }

  /// 启动位置推进定时器（视图 attach 后调用）。
  ///
  /// 用 30Hz 的定时器而不是帧回调：`video_player` 每 500ms 才回报一次位置，
  /// 弹幕在两次回报之间靠本地时钟外推，30Hz 足以让滚动看起来连续，
  /// 又不会像 60Hz 那样把整棵播放器视图树 rebuild 60 次每秒。
  void attachTicker() {
    _timer ??= Timer.periodic(
        const Duration(milliseconds: 33), (_) => _onTick(Duration.zero));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _surface.dispose();
    super.dispose();
  }
}
