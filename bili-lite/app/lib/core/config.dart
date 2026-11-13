import 'package:flutter/foundation.dart';

import 'api_paths.dart';

/// 服务端地址的多端适配。
///
/// Web 由 BFF 同源托管，直接使用相对路径 `/api/...`，无需跨域配置；
/// 桌面 / iOS 模拟器走 127.0.0.1，Android 模拟器走 10.0.2.2；
/// 真机调试用 `--dart-define=BFF_URL=http://<电脑IP>:8787` 覆盖。
class ApiConfig {
  ApiConfig._();

  static const String _override =
      String.fromEnvironment('BFF_URL', defaultValue: '');

  static const int defaultPort = 8787;

  /// 纯离线开关：用 `--dart-define=OFFLINE=1` 打开。
  /// 此时不发任何网络请求，直接读取 assets/offline.json 里的真实数据快照。
  /// 默认关闭——独立安装包会自行直连 B 站公开接口，只有断网 / 风控时才
  /// 自动降级到这份快照，所以不再依赖用户电脑上跑着 Node BFF。
  static const String _offlineFlag =
      String.fromEnvironment('OFFLINE', defaultValue: '');

  static bool get offline =>
      _offlineFlag.isNotEmpty &&
      _offlineFlag != '0' &&
      _offlineFlag.toLowerCase() != 'false';

  /// 原生端直连 B 站公开接口，默认开启。
  /// Web 端受浏览器 CORS 限制必须走同源 BFF；显式指定 BFF_URL 时以调试配置为准。
  static bool get direct => !offline && !kIsWeb && _override.isEmpty;

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return '';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$defaultPort';
    }
    return 'http://127.0.0.1:$defaultPort';
  }

  /// 拼一个 API 地址。query 里的空值会被自动丢弃。
  static String url(String path, [Map<String, String>? query]) {
    final buffer = StringBuffer('$baseUrl$path');
    if (query != null) {
      final pairs = query.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .toList();
      if (pairs.isNotEmpty) buffer.write('?${pairs.join('&')}');
    }
    return buffer.toString();
  }

  /// 图片：Web 走 BFF 代理（规避混合内容与 referer 防盗链）；
  /// 原生端直连没有这些限制，直接用 https 原图，也不需要本机 BFF。
  static String image(String raw) {
    if (raw.isEmpty) return '';
    var normalized = raw;
    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    } else if (normalized.startsWith('http://')) {
      normalized = 'https://${normalized.substring(7)}';
    }
    if (offline || direct) return normalized;
    return url('/api/img', {'url': normalized});
  }

  /// 官方 OAuth 必须经过授权服务端：client_secret 只能留在服务端，客户端拿不到也不该拿到。
  /// 因此这里不走「原生直连 B 站」的链路，始终指向 BFF（或显式配置的 BFF_URL）。
  static String oauthUrl(String path) {
    final base = _override.isNotEmpty ? _override : (kIsWeb ? '' : baseUrl);
    return '$base$path';
  }

  /// OAuth 服务地址（给用户看的说明）
  static String get oauthDisplayBase {
    if (_override.isNotEmpty) return _override;
    return kIsWeb ? '当前同源服务' : baseUrl;
  }

  /// 统一的接口路径表已抽到 `core/api_paths.dart`。
  ///
  /// 抽出去的原因：路径表与运行环境无关，而本文件需要 Flutter 框架才能
  /// 判断 kIsWeb / defaultTargetPlatform。留在这里会让 `data/` 层的直连
  /// 实现间接依赖 Flutter，使得纯 Dart 冒烟脚本无法运行。
  ///
  /// 这里保留一组转发常量，避免调用方大范围改动；
  /// 新增接口请直接改 `ApiPaths`。
  static const String apiHealth = ApiPaths.health;
  static const String apiMeta = ApiPaths.meta;
  static const String apiFeed = ApiPaths.feed;
  static const String apiRank = ApiPaths.rank;
  static const String apiPopular = ApiPaths.popular;
  static const String apiSearch = ApiPaths.search;
  static const String apiVideo = ApiPaths.video;
  static const String apiReply = ApiPaths.reply;

  static const Map<String, String> endpoints = ApiPaths.endpoints;

  /// 取接口路径。未知 key 返回空串（调用方不会用到）。
  static String endpoint(String key) => ApiPaths.endpoint(key);

  /// 给用户看的当前服务地址说明
  static String get displayBase {
    if (offline) return '内置离线快照';
    if (direct) return 'api.bilibili.com（直连）';
    return kIsWeb && _override.isEmpty ? '当前同源服务' : baseUrl;
  }
}
