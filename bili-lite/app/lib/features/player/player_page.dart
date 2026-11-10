import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/bili_player.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/glass.dart';
import 'player_view.dart';

/// 应用内播放页：嵌入 B 站官方站外播放器，用户不离开应用即可观看。
///
/// 边界：播放器由 player.bilibili.com 提供，本应用不解析播放地址、
/// 不接触视频流、不注入登录态；需要账号的互动引导到官方客户端完成。
class PlayerPage extends StatelessWidget {
  const PlayerPage({Key? key, required this.video, this.page = 1})
      : super(key: key);

  final Video video;
  final int page;

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await canLaunchUrl(uri)
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      if (!ok) _notifyOpenFailed(context);
    } catch (_) {
      _notifyOpenFailed(context);
    }
  }

  // ignore: use_build_context_synchronously
  void _notifyOpenFailed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('无法打开，请在浏览器中访问官方视频页'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    final embedUrl = BiliPlayer.embedUrl(
      bvid: video.bvid,
      aid: video.aid,
      page: page,
    );
    final embedded = buildOfficialPlayer(embedUrl);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: embedded ?? _fallback(context, embedUrl, sub),
                  ),
                ),
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 14,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.play_circle_outline_rounded,
                              size: 16, color: AppColors.pink),
                          const SizedBox(width: 7),
                          Text('B 站官方外链播放器',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: dark
                                      ? AppColors.darkText
                                      : AppColors.lightText)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '播放能力、清晰度与版权控制由官方播放器负责，本应用只传入 BV 号与分 P，'
                        '不解析播放地址、不接触视频流、不保存任何账号或登录凭证。'
                        '部分 UP 主可关闭「允许嵌入」，此时播放器会提示前往官方观看。',
                        style: TextStyle(fontSize: 11.5, color: sub, height: 1.6),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          GlassChip(
                            label: '评论 / 投币 / 点赞（官方客户端）',
                            icon: Icons.open_in_new_rounded,
                            tint: AppColors.pink,
                            radius: 11,
                            onTap: () => _launch(
                                context, BiliPlayer.officialPage(video.bvid)),
                          ),
                          GlassChip(
                            label: '官方播放器文档',
                            icon: Icons.description_outlined,
                            radius: 11,
                            onTap: () =>
                                _launch(context, BiliPlayer.docsUrl),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 原生端降级：不伪造播放器，用系统浏览器打开同一个官方外链播放器页面。
  Widget _fallback(BuildContext context, String url, Color sub) {
    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.smart_display_outlined,
              size: 42, color: AppColors.pink),
          const SizedBox(height: 12),
          Text('在官方播放器中观看',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkText
                      : AppColors.lightText)),
          const SizedBox(height: 8),
          Text(
            '当前平台没有可用的官方嵌入组件，将打开 B 站官方外链播放器页面。'
            '应用不会自行解析视频源或代持登录态。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: sub, height: 1.6),
          ),
          const SizedBox(height: 14),
          GlassChip(
            label: '打开官方播放器',
            icon: Icons.play_arrow_rounded,
            tint: AppColors.pink,
            radius: 11,
            onTap: () => _launch(context, url),
          ),
        ],
      ),
    );
  }
}
