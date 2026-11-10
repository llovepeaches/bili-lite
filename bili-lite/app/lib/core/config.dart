import 'package:flutter/foundation.dart';

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

  /// 独立安装包模式：用 `--dart-define=OFFLINE=1` 打开。
  /// 此时不发任何网络请求，直接读取 assets/offline.json 里的真实数据快照，
  /// 封面走原始 https 图床，App 装到真机即可离线使用。
  static const String _offlineFlag =
      String.fromEnvironment('OFFLINE', defaultValue: '');

  static bool get offline =>
      _offlineFlag.isNotEmpty &&
      _offlineFlag != '0' &&
      _offlineFlag.toLowerCase() != 'false';

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

  /// 图片统一走 BFF 代理：规避 Web 端混合内容与 referer 防盗链。
  static String image(String raw) {
    if (raw.isEmpty) return '';
    if (offline) return raw.startsWith('//') ? 'https:$raw' : raw;
    return url('/api/img', {'url': raw});
  }

  static const Map<String, String> endpoints = {
    'health': '/api/health',
    'meta': '/api/meta',
    'feed': '/api/feed',
    'rank': '/api/rank',
    'popular': '/api/popular',
    'search': '/api/search',
    'video': '/api/video',
    'reply': '/api/reply',
  };

  /// 给用户看的当前服务地址说明
  static String get displayBase => offline
      ? '内置离线快照'
      : (kIsWeb && _override.isEmpty ? '当前同源服务' : baseUrl);
}
