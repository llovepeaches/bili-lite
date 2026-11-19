import 'dart:convert';

import 'package:bililite/core/app_version.dart';
import 'package:bililite/state/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final http.Response Function(http.BaseRequest request) _handler;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final res = _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }
}

http.Response _json(int status, Object body) => http.Response(
      json.encode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

void main() {
  group('版本号与发布 tag', () {
    test('语义化版本比较', () {
      expect(compareSemver('0.2.0', '0.1.0'), 1);
      expect(compareSemver('0.1.0', '0.1.0'), 0);
      expect(compareSemver('0.1.0', '0.1.1'), -1);
      expect(compareSemver('0.10.0', '0.9.9'), 1);
      expect(compareSemver('v1.0.0', '0.9.9'), 1);
      expect(compareSemver('0.1.0+1', '0.1.0'), 0);
      expect(compareSemver('nope', '0.1.0'), isNull);
    });

    test('只识别 bili-lite-v 前缀的发布标记', () {
      expect(versionFromTag('bili-lite-v0.2.0'), '0.2.0');
      expect(versionFromTag('bili-lite-v0.1.0'), '0.1.0');
      expect(versionFromTag('v1.6.0'), isNull);
      expect(versionFromTag('bili-lite-vnope'), isNull);
      expect(versionFromTag(''), isNull);
    });

    test('应用内版本与发布 tag 由同一常量派生', () {
      // 写死版本号是有意的漂移守卫：发版时若忘了改 app_version.dart，
      // 这里会立刻失败，而不是等到 CI 的 Verify version sync 才暴露。
      expect(kAppVersion, '0.1.5');
      // 从 v0.1.4 起，用户可见版本串只显示三段版本号，不拼 +构建号。
      expect(kAppVersionLabel, kAppVersion);
      expect(kAppVersionLabel, isNot(contains('+')));
      expect(kReleaseTag, 'bili-lite-v$kAppVersion');
      expect(versionFromTag(kReleaseTag), kAppVersion);
    });
  });

  group('更新检查', () {
    test('远端版本更高时报告可用更新与下载地址', () async {
      final client = _FakeClient((_) => _json(200, <String, dynamic>{
            'tag_name': 'bili-lite-v0.2.0',
            'html_url':
                'https://github.com/llovepeaches/bili-lite/releases/tag/bili-lite-v0.2.0',
          }));
      final info = await UpdateService(client: client).check();
      expect(info.status, UpdateCheckStatus.available);
      expect(info.hasUpdate, true);
      expect(info.latestVersion, '0.2.0');
      expect(info.releaseUrl, contains('0.2.0'));
      expect(client.calls, 1);
    });

    test('远端版本相同时显示已是最新', () async {
      final client = _FakeClient((_) => _json(200, <String, dynamic>{
            'tag_name': kReleaseTag,
            'html_url': kReleasesPage,
          }));
      final info = await UpdateService(client: client).check();
      expect(info.status, UpdateCheckStatus.upToDate);
      expect(info.hasUpdate, false);
    });

    test('历史 tag 前缀不符时降级失败，绝不误报更新', () async {
      final client = _FakeClient((_) => _json(200, <String, dynamic>{
            'tag_name': 'v1.6.0',
            'html_url': kReleasesPage,
          }));
      final info = await UpdateService(client: client).check();
      expect(info.status, UpdateCheckStatus.failed);
      expect(info.hasUpdate, false);
      expect(info.message, contains('未识别'));
    });

    test('限流 / 无发布记录 / 服务异常都温和降级', () async {
      for (final code in <int>[403, 404, 500]) {
        final client = _FakeClient((_) => http.Response('', code));
        final info = await UpdateService(client: client).check();
        expect(info.status, UpdateCheckStatus.failed, reason: 'HTTP $code');
        expect(info.message, isNotEmpty);
        expect(info.hasUpdate, false);
      }
    });

    test('非法 JSON 与网络异常不会抛出，也不会当成有更新', () async {
      final badJson = _FakeClient((_) => http.Response('[]', 200));
      final a = await UpdateService(client: badJson).check();
      expect(a.status, UpdateCheckStatus.failed);
      expect(a.hasUpdate, false);

      final offline = _FakeClient((_) => throw StateError('离线'));
      final b = await UpdateService(client: offline).check();
      expect(b.status, UpdateCheckStatus.failed);
      expect(b.hasUpdate, false);
      expect(b.message, contains('网络不可用'));
    });
  });
}
