import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';

/// UP 主资料卡。
class SpaceOwnerCard extends StatelessWidget {
  const SpaceOwnerCard({Key? key, required this.owner}) : super(key: key);

  final Owner owner;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          UserAvatar(url: owner.face, name: owner.name, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('UID ${owner.mid}',
                    style: TextStyle(fontSize: 11.5, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空间稿件列表的一行。
class SpaceVideoRow extends StatelessWidget {
  const SpaceVideoRow({Key? key, required this.video}) : super(key: key);

  final Video video;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.all(10),
        onTap: () => openVideoDetail(context, video),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 132,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CoverImage(url: video.cover, radius: 10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title.isEmpty ? '（无标题）' : video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Fmt.compact(video.stat.view)} 播放 · ${video.durationText}',
                    style: TextStyle(fontSize: 11, color: sub),
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

/// 加载失败 / 空结果提示。
class SpaceNotice extends StatelessWidget {
  const SpaceNotice({
    Key? key,
    required this.message,
    required this.onRetry,
  }) : super(key: key);

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.subTextColor)),
            const SizedBox(height: 12),
            GlassChip(
              label: '重试',
              icon: Icons.refresh_rounded,
              tint: AppColors.pink,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
