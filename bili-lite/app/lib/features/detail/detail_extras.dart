import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/glass.dart';

/// 详情页的 BV 号徽标。
///
/// 之前详情页只有标题、统计、UP 主，想复制 BV 号只能回列表页长按或去原站，
/// 这里直接把稿件的 bvid 显示出来，点一下就复制。
class BvBadge extends StatelessWidget {
  const BvBadge({Key? key, required this.bvid}) : super(key: key);

  final String bvid;

  @override
  Widget build(BuildContext context) {
    if (bvid.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _copy(context, bvid, '已复制 BV 号'),
      child: GlassPill(
        radius: 8,
        tint: AppColors.pink.withOpacity(0.12),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.numbers_rounded, size: 13, color: AppColors.pink),
            const SizedBox(width: 5),
            Text(
              bvid,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3),
            ),
            const SizedBox(width: 5),
            Icon(Icons.copy_all_rounded,
                size: 12, color: AppColors.pink.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}

/// 「官方原版内容」文本：标题 + UP 主 + 官方链接，可直接转发。
///
/// 抽成纯函数是为了单测能固定住格式，避免以后改分享面板时不小心
/// 把官方链接或 UP 主丢掉。
String officialShareText(Video video) => <String>[
      video.title,
      if (video.owner.name.isNotEmpty) 'UP 主：${video.owner.name}',
      video.webUrl,
    ].join('\n');

/// 分享面板：把「原版官方内容」真正带出来。
///
/// 旧行为是点「分享」直接 `launchUrl` 跳官方客户端，用户既拿不到可转发的
/// 文本，也不知道分享的是什么。现在提供三条明确动作，其中「标题 + UP 主 +
/// 官方链接」就是可以直接粘贴到任意聊天窗口的官方原版内容。
///
/// [onOpenExternal] 由调用方传入，避免这里反向 import detail_view.dart
/// 形成库循环。
Future<void> showVideoShareSheet(
  BuildContext context, {
  required Video video,
  required Future<void> Function(String url) onOpenExternal,
}) async {
  final officialText = officialShareText(video);

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: GlassPanel(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('分享',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                video.webUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: sheetContext.subTextColor),
              ),
              const SizedBox(height: 12),
              _ShareAction(
                icon: Icons.link_rounded,
                title: '复制官方原版链接',
                subtitle: video.webUrl,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _copy(context, video.webUrl, '已复制官方链接');
                },
              ),
              _ShareAction(
                icon: Icons.article_outlined,
                title: '复制标题 + UP 主 + 链接',
                subtitle: '可直接转发的官方原版内容',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _copy(context, officialText, '已复制官方原版内容');
                },
              ),
              _ShareAction(
                icon: Icons.open_in_new_rounded,
                title: '在官方客户端打开',
                subtitle: '跳转 B 站官方页面',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onOpenExternal(video.webUrl);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 分享面板里的一行动作。
class _ShareAction extends StatelessWidget {
  const _ShareAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: AppColors.pink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5, color: context.subTextColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet)),
    ),
  );
}
