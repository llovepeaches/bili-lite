/// BFF 统一数据模型。客户端只认识这里的结构，上游字段变化被隔离在服务端。
library models;

String _s(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  // 上游偶尔把 reason 这类字段塞成对象，直接 toString 会得到 "[object Object]"。
  if (v is Map) {
    for (final key in <String>['content', 'reason', 'text', 'name']) {
      final nested = _s(v[key]);
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }
  if (v is List) {
    for (final item in v) {
      final nested = _s(item);
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }
  return v.toString();
}

int _i(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(_s(v)) ?? 0;
}

bool _b(dynamic v) => v == true;

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _l(dynamic v) =>
    v is List ? List<dynamic>.from(v) : <dynamic>[];

class Owner {
  final String mid;
  final String name;
  final String face;

  const Owner({this.mid = '', this.name = '', this.face = ''});

  factory Owner.fromJson(dynamic raw) {
    final j = _m(raw);
    final name = _s(j['name']);
    return Owner(
      mid: _s(j['mid']),
      name: name.isEmpty ? '未知 UP 主' : name,
      face: _s(j['face']),
    );
  }

  Map<String, dynamic> toJson() => {'mid': mid, 'name': name, 'face': face};
}

class Stat {
  final int view;
  final int danmaku;
  final int reply;
  final int like;
  final int coin;
  final int favorite;
  final int share;

  const Stat({
    this.view = 0,
    this.danmaku = 0,
    this.reply = 0,
    this.like = 0,
    this.coin = 0,
    this.favorite = 0,
    this.share = 0,
  });

  factory Stat.fromJson(dynamic raw) {
    final j = _m(raw);
    return Stat(
      view: _i(j['view']),
      danmaku: _i(j['danmaku']),
      reply: _i(j['reply']),
      like: _i(j['like']),
      coin: _i(j['coin']),
      favorite: _i(j['favorite']),
      share: _i(j['share']),
    );
  }

  Map<String, dynamic> toJson() => {
        'view': view,
        'danmaku': danmaku,
        'reply': reply,
        'like': like,
        'coin': coin,
        'favorite': favorite,
        'share': share,
      };
}

class Video {
  final String aid;
  final String bvid;
  final String cid;
  final String title;
  final String cover;
  final int duration;
  final String durationText;
  final Owner owner;
  final Stat stat;
  final int pubdate;
  final String desc;
  final String tname;
  final String reason;

  const Video({
    this.aid = '',
    this.bvid = '',
    this.cid = '',
    this.title = '',
    this.cover = '',
    this.duration = 0,
    this.durationText = '',
    this.owner = const Owner(),
    this.stat = const Stat(),
    this.pubdate = 0,
    this.desc = '',
    this.tname = '',
    this.reason = '',
  });

  factory Video.fromJson(dynamic raw) {
    final j = _m(raw);
    return Video(
      aid: _s(j['aid']),
      bvid: _s(j['bvid']),
      cid: _s(j['cid']),
      title: _s(j['title']),
      cover: _s(j['cover']),
      duration: _i(j['duration']),
      durationText: _s(j['durationText']),
      owner: Owner.fromJson(j['owner']),
      stat: Stat.fromJson(j['stat']),
      pubdate: _i(j['pubdate']),
      desc: _s(j['desc']),
      tname: _s(j['tname']),
      reason: _s(j['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'aid': aid,
        'bvid': bvid,
        'cid': cid,
        'title': title,
        'cover': cover,
        'duration': duration,
        'durationText': durationText,
        'owner': owner.toJson(),
        'stat': stat.toJson(),
        'pubdate': pubdate,
        'desc': desc,
        'tname': tname,
        'reason': reason,
      };

  String get webUrl => 'https://www.bilibili.com/video/$bvid';
}

class PageInfo {
  final String cid;
  final int page;
  final String part;
  final int duration;
  final String durationText;

  const PageInfo({
    this.cid = '',
    this.page = 1,
    this.part = '',
    this.duration = 0,
    this.durationText = '',
  });

  factory PageInfo.fromJson(dynamic raw) {
    final j = _m(raw);
    return PageInfo(
      cid: _s(j['cid']),
      page: _i(j['page']),
      part: _s(j['part']),
      duration: _i(j['duration']),
      durationText: _s(j['durationText']),
    );
  }
}

class VideoDetail {
  final Video video;
  final List<PageInfo> pages;
  final String dynamicText;
  final List<String> tags;

  const VideoDetail({
    required this.video,
    this.pages = const <PageInfo>[],
    this.dynamicText = '',
    this.tags = const <String>[],
  });

  factory VideoDetail.fromJson(dynamic raw) {
    final j = _m(raw);
    return VideoDetail(
      video: Video.fromJson(j),
      pages: _l(j['pages']).map((e) => PageInfo.fromJson(e)).toList(),
      dynamicText: _s(j['dynamic']),
      tags: _l(j['tags']).map((e) => _s(e)).toList(),
    );
  }
}

class SubReply {
  final String id;
  final String uname;
  final String message;
  final int ctime;

  const SubReply({this.id = '', this.uname = '', this.message = '', this.ctime = 0});

  factory SubReply.fromJson(dynamic raw) {
    final j = _m(raw);
    return SubReply(
      id: _s(j['id']),
      uname: _s(j['uname']),
      message: _s(j['message']),
      ctime: _i(j['ctime']),
    );
  }
}

class Comment {
  final String id;
  final String mid;
  final String uname;
  final String avatar;
  final int level;
  final String message;
  final int like;
  final int replyCount;
  final int ctime;
  final bool isTop;
  final String location;
  final List<SubReply> replies;

  const Comment({
    this.id = '',
    this.mid = '',
    this.uname = '',
    this.avatar = '',
    this.level = 0,
    this.message = '',
    this.like = 0,
    this.replyCount = 0,
    this.ctime = 0,
    this.isTop = false,
    this.location = '',
    this.replies = const <SubReply>[],
  });

  factory Comment.fromJson(dynamic raw) {
    final j = _m(raw);
    return Comment(
      id: _s(j['id']),
      mid: _s(j['mid']),
      uname: _s(j['uname']),
      avatar: _s(j['avatar']),
      level: _i(j['level']),
      message: _s(j['message']),
      like: _i(j['like']),
      replyCount: _i(j['replyCount']),
      ctime: _i(j['ctime']),
      isTop: _b(j['isTop']),
      location: _s(j['location']),
      replies: _l(j['replies']).map((e) => SubReply.fromJson(e)).toList(),
    );
  }
}

class CommentPage {
  final int count;
  final List<Comment> list;

  const CommentPage({this.count = 0, this.list = const <Comment>[]});

  factory CommentPage.fromJson(dynamic raw) {
    final j = _m(raw);
    return CommentPage(
      count: _i(j['count']),
      list: _l(j['list']).map((e) => Comment.fromJson(e)).toList(),
    );
  }
}

class SearchResult {
  final int page;
  final int pages;
  final int total;
  final List<Video> list;

  const SearchResult({
    this.page = 1,
    this.pages = 0,
    this.total = 0,
    this.list = const <Video>[],
  });

  factory SearchResult.fromJson(dynamic raw) {
    final j = _m(raw);
    return SearchResult(
      page: _i(j['page']),
      pages: _i(j['pages']),
      total: _i(j['total']),
      list: _l(j['list']).map((e) => Video.fromJson(e)).toList(),
    );
  }
}

class RankResult {
  final String note;
  final List<Video> list;

  const RankResult({this.note = '', this.list = const <Video>[]});

  factory RankResult.fromJson(dynamic raw) {
    final j = _m(raw);
    return RankResult(
      note: _s(j['note']),
      list: _l(j['list']).map((e) => Video.fromJson(e)).toList(),
    );
  }
}

class Partition {
  final int rid;
  final String name;

  const Partition({this.rid = 0, this.name = ''});

  factory Partition.fromJson(dynamic raw) {
    final j = _m(raw);
    return Partition(rid: _i(j['rid']), name: _s(j['name']));
  }
}

class HealthInfo {
  final String version;
  final bool mockMode;
  final String identity;
  final String snapshotAt;
  final int cacheEntries;
  final bool webBuild;
  final int uptime;

  const HealthInfo({
    this.version = '',
    this.mockMode = false,
    this.identity = '',
    this.snapshotAt = '',
    this.cacheEntries = 0,
    this.webBuild = false,
    this.uptime = 0,
  });

  factory HealthInfo.fromJson(dynamic raw) {
    final j = _m(raw);
    return HealthInfo(
      version: _s(j['version']),
      mockMode: _b(j['mockMode']),
      identity: _s(j['identity']),
      snapshotAt: _s(j['snapshotAt']),
      cacheEntries: _i(j['cacheEntries']),
      webBuild: _b(j['webBuild']),
      uptime: _i(j['uptime']),
    );
  }
}

class MetaInfo {
  final List<Partition> partitions;
  final List<Map<String, dynamic>> replySorts;

  const MetaInfo({
    this.partitions = const <Partition>[],
    this.replySorts = const <Map<String, dynamic>>[],
  });

  factory MetaInfo.fromJson(dynamic raw) {
    final j = _m(raw);
    return MetaInfo(
      partitions: _l(j['partitions']).map((e) => Partition.fromJson(e)).toList(),
      replySorts: _l(j['replySorts'])
          .map((e) => Map<String, dynamic>.from(_m(e)))
          .toList(),
    );
  }
}

/// 所有接口的外层响应，附带数据来源标记（live / cache / mock）
class ApiResponse<T> {
  final T data;
  final String source;
  final bool stale;

  const ApiResponse({required this.data, this.source = 'live', this.stale = false});

  bool get isOffline => source == 'mock' || stale;
}

/// 播放地址。
///
/// 取 B 站 playurl 的 `durl`（单文件 mp4）：渐进式播放、不需要合流器，
/// 六端行为一致。DASH 是音视频分离的 m4s，需要各端自建合流逻辑，不适合。
class PlayUrl {
  final String url;
  final String backupUrl;
  final int size;
  final int quality;
  final String qualityLabel;
  final int timelength;

  const PlayUrl({
    this.url = '',
    this.backupUrl = '',
    this.size = 0,
    this.quality = 0,
    this.qualityLabel = '',
    this.timelength = 0,
  });

  bool get playable => url.isNotEmpty;

  /// 视频时长（毫秒）。
  int get durationMs => timelength;

  factory PlayUrl.fromJson(dynamic raw) {
    final j = _m(raw);
    return PlayUrl(
      url: _s(j['url']),
      backupUrl: _s(j['backupUrl']),
      size: _i(j['size']),
      quality: _i(j['quality']),
      qualityLabel: _s(j['qualityLabel']),
      timelength: _i(j['timelength']),
    );
  }
}

/// 一条弹幕。
///
/// [mode] 沿用 B 站的定义：1 = 滚动、4 = 底部固定、5 = 顶部固定。
/// [time] 是毫秒时间戳，播放器按播放进度取用。
class Danmaku {
  final int time;
  final int mode;
  final int size;
  final int color;
  final String text;

  const Danmaku({
    this.time = 0,
    this.mode = 1,
    this.size = 25,
    this.color = 0xffffff,
    this.text = '',
  });

  factory Danmaku.fromJson(dynamic raw) {
    final j = _m(raw);
    return Danmaku(
      time: _i(j['time']),
      mode: _i(j['mode']),
      size: _i(j['size']),
      color: _i(j['color']),
      text: _s(j['text']),
    );
  }
}

/// 弹幕列表。
class DanmakuList {
  final int count;
  final List<Danmaku> list;

  const DanmakuList({this.count = 0, this.list = const <Danmaku>[]});

  bool get isEmpty => list.isEmpty;

  factory DanmakuList.fromJson(dynamic raw) {
    final j = _m(raw);
    final items = _l(j['list']).map((e) => Danmaku.fromJson(e)).toList();
    return DanmakuList(count: _i(j['count']), list: items);
  }
}
