import 'package:url_launcher/url_launcher.dart';

/// 原生端：用系统浏览器打开官方授权页。
/// 用户在系统浏览器完成授权后，回调页会给出一次性授权码与深链，
/// 回到应用粘贴即可（client_secret 始终留在授权服务端）。
Future<bool> openAuthorizeUrl(String url) async {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
