/// 统一的接口路径表（纯 Dart，不依赖 Flutter 框架）。
///
/// 为什么单独成文件：
/// `core/config.dart` 需要 `package:flutter/foundation.dart` 才能拿到
/// `kIsWeb` 与 `defaultTargetPlatform`，因此依赖它的代码无法在纯 Dart VM
/// 里运行——`tool/verify_live.dart`（原生端直连冒烟脚本）就是这样变成
/// 一段「注释里声称可用、实际永远跑不通」的代码（dart:ui 缺失）。
///
/// 路径表本身与运行环境无关，拆出来之后：
///   * `data/` 层的直连实现只依赖本文件，不牵动 Flutter；
///   * `config.dart` 只负责「地址怎么算」，不再兼管「有哪些接口」。

/// 服务端接口路径。
///
/// 之前这张表定义在 `core/config.dart` 里却从未被调用方使用，
/// `BiliRepository` 全部硬编码 '/api/feed'、'/api/rank'……，
/// 于是「改常量不改调用点」成了最容易漏的坑。现在是唯一数据源。
///
/// 用具名 const 字段而不是 Map 查表，是为了让 `case ApiPaths.apiFeed:`
/// 这类 switch 分支能写成编译期常量（Dart 的 case 标签不接受函数调用结果）。
class ApiPaths {
  ApiPaths._();

  static const String health = '/api/health';
  static const String meta = '/api/meta';
  static const String feed = '/api/feed';
  static const String rank = '/api/rank';
  static const String popular = '/api/popular';
  static const String search = '/api/search';
  static const String video = '/api/video';
  static const String reply = '/api/reply';

  /// 应用内播放：解析 mp4 直链（fnval=1 的 durl）。
  static const String playurl = '/api/playurl';

  /// 弹幕：上游是 deflate 压缩的 XML，服务端解压后转成 JSON。
  static const String danmaku = '/api/danmaku';

  static const Map<String, String> endpoints = <String, String>{
    'health': health,
    'meta': meta,
    'feed': feed,
    'rank': rank,
    'popular': popular,
    'search': search,
    'video': video,
    'reply': reply,
    'playurl': playurl,
    'danmaku': danmaku,
  };

  /// 取接口路径。未知 key 返回空串（调用方不会用到）。
  static String endpoint(String key) => endpoints[key] ?? '';
}
