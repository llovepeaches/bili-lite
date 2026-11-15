import 'package:bililite/data/oauth_api.dart';
import 'package:bililite/state/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 计数用的假 HTTP 客户端：任何请求都会计数并立刻失败。
class _CountingClient extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('启动关键路径不应发起网络请求：${request.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initLocal 只恢复本地凭证，不发起任何网络请求', () async {
    final client = _CountingClient();
    OAuthApi.instance.debugClient = client;

    final session = AuthSession();
    await session.initLocal();

    expect(client.requests, 0,
        reason: 'BFF 探活必须留在 runApp 之后，否则独立安装包会白屏等满超时');
    expect(session.status, AuthStatus.unknown);
  });

  test('init 的 BFF 探活失败被兜底为 unavailable，不影响调用方', () async {
    final client = _CountingClient();
    OAuthApi.instance.debugClient = client;

    final session = AuthSession();
    await session.init();

    expect(client.requests, 1, reason: '完整初始化仍应执行探活');
    expect(session.status, AuthStatus.unavailable);
  });
}
