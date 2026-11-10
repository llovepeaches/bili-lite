// Web 端：官方授权页需要同页导航，回调后才能自动恢复登录态。
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web 端：同页导航到官方授权页。
/// 授权完成后 BFF 会 302 回 `/?oauth_ticket=...`，App 重新加载时自动领取，
/// 这样登录态与当前页面始终是同一份，不需要跨标签同步。
Future<bool> openAuthorizeUrl(String url) async {
  html.window.location.assign(url);
  return true;
}
