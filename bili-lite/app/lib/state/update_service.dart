import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:http/http.dart' as http;

import '../core/app_version.dart';
import '../core/storage.dart';

enum UpdateCheckStatus { idle, checking, upToDate, available, failed }

/// 一次检查的结果。只携带公开信息，不含任何本机数据。
class UpdateInfo {
  const UpdateInfo(
    this.status, {
    this.latestVersion,
    this.releaseUrl,
    this.message,
  });

  final UpdateCheckStatus status;
  final String? latestVersion;
  final String? releaseUrl;
  final String? message;

  bool get hasUpdate => status == UpdateCheckStatus.available;
}

/// 应用内更新检查。
///
/// 数据源是 GitHub Releases 的公开 `releases/latest` 接口，不需要自建服务端。
/// 设计约束：
///   * 手动检查与启动后静默检查都**不阻塞首屏**（由 main 在 runApp 之后调度）；
///   * 静默检查 12 小时最多一次，避免浪费 GitHub 未认证接口的 60 次/小时配额；
///   * 任何异常（离线、限流、解析失败、超时）都返回 failed，由 UI 温和提示，
///     绝不弹窗、绝不把「检查不了」误报成「有新版本」；
///   * Web 端不设置自定义 User-Agent（浏览器禁止，会触发 CORS 预检失败）。
class UpdateService extends ChangeNotifier {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static final UpdateService instance = UpdateService();

  final http.Client _client;

  static const String _kLastAutoCheck = 'bili_lite_update_last_auto_check';
  static const Duration _autoInterval = Duration(hours: 12);
  static const Duration _requestTimeout = Duration(seconds: 6);

  UpdateInfo? _last;
  UpdateInfo? get last => _last;

  bool _checking = false;
  bool get checking => _checking;

  /// 手动检查（设置页按钮）。重复点击会复用进行中的结果。
  Future<UpdateInfo> check() async {
    if (_checking) {
      return _last ?? const UpdateInfo(UpdateCheckStatus.checking);
    }
    _checking = true;
    notifyListeners();
    final result = await _fetch();
    _last = result;
    _checking = false;
    notifyListeners();
    return result;
  }

  /// 启动后的静默检查：12 小时内最多一次，结果缓存在 [last] 供设置页直接展示。
  Future<UpdateInfo?> autoCheck() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAt = LocalStore.instance.getInt(_kLastAutoCheck) ?? 0;
    if (now - lastAt < _autoInterval.inMilliseconds) return _last;
    await LocalStore.instance.setInt(_kLastAutoCheck, now);
    return check();
  }

  Future<UpdateInfo> _fetch() async {
    try {
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        if (!kIsWeb) 'User-Agent': 'bili-lite/$kAppVersion',
      };
      final res = await _client
          .get(Uri.parse(kReleasesLatestApi), headers: headers)
          .timeout(_requestTimeout);

      if (res.statusCode == 404) {
        return const UpdateInfo(UpdateCheckStatus.failed,
            message: '暂无发布记录，请稍后再试');
      }
      if (res.statusCode == 403) {
        return const UpdateInfo(UpdateCheckStatus.failed,
            message: 'GitHub 接口访问过频，请稍后再试或直接打开发布页');
      }
      if (res.statusCode != 200) {
        return UpdateInfo(UpdateCheckStatus.failed,
            message: '检查失败（HTTP ${res.statusCode}）');
      }

      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) {
        return const UpdateInfo(UpdateCheckStatus.failed,
            message: '返回内容格式异常');
      }
      final tag = (decoded['tag_name'] ?? '').toString();
      final latest = versionFromTag(tag);
      if (latest == null) {
        return UpdateInfo(UpdateCheckStatus.failed,
            message: '未识别的发布标记：$tag');
      }
      final cmp = compareSemver(latest, kAppVersion);
      if (cmp == null) {
        return UpdateInfo(UpdateCheckStatus.failed,
            message: '版本号无法比较：$latest');
      }
      final url = (decoded['html_url'] ?? kReleasesPage).toString();
      if (cmp > 0) {
        return UpdateInfo(
          UpdateCheckStatus.available,
          latestVersion: latest,
          releaseUrl: url,
          message: '发现新版本 v$latest，可前往发布页下载',
        );
      }
      return UpdateInfo(
        UpdateCheckStatus.upToDate,
        latestVersion: latest,
        releaseUrl: url,
        message: '已是最新版本 v$latest',
      );
    } catch (_) {
      return const UpdateInfo(
        UpdateCheckStatus.failed,
        message: '网络不可用或暂时无法连接 GitHub，请稍后重试',
      );
    }
  }
}
