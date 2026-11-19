import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../state/globals.dart';
import '../../state/library_state.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/glass.dart';
import 'detail_controller.dart';
import 'detail_external.dart';
import 'detail_extras.dart';

/// AppBar 右侧的胶囊工具组：收藏 / 稍后再看 / 播放 / 原站。
class DetailToolGroup extends StatelessWidget {
  const DetailToolGroup({Key? key, required this.controller}) : super(key: key);

  final DetailController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AnimatedBuilder(
        animation: library,
        builder: (context, _) {
          final video = controller.resolvedVideo;
          final favorite = library.isFavorite(video.bvid);
          final later = library.inWatchLater(video.bvid);
          return GlassPanel(
            radius: AppRadius.pill,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DetailToolButton(
                  icon: favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  tooltip: favorite ? '取消收藏' : '收藏',
                  active: favorite,
                  onTap: () => library.toggle(LibraryKind.favorites, video),
                ),
                DetailToolButton(
                  icon: later
                      ? Icons.watch_later_rounded
                      : Icons.watch_later_outlined,
                  tooltip: later ? '移出稍后再看' : '稍后再看',
                  active: later,
                  onTap: () => library.toggle(LibraryKind.watchLater, video),
                ),
                DetailToolButton(
                  icon: Icons.play_circle_outline_rounded,
                  tooltip: '播放',
                  // 详情页内嵌播放：起播后按钮变为幂等，不再 push 播放页。
                  onTap: controller.startPlayback,
                ),
                DetailToolButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: '在官方客户端打开',
                  onTap: () => openExternal(context, video.webUrl),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 工具组里的单个图标按钮。
class DetailToolButton extends StatelessWidget {
  const DetailToolButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  }) : super(key: key);

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 19,
            color: active ? AppColors.pink : context.primaryTextColor,
          ),
        ),
      ),
    );
  }
}

/// UP 主卡片：头像 + 名字 + UID，右侧一个「查看主页」入口。
class DetailOwnerCard extends StatelessWidget {
  const DetailOwnerCard({
    Key? key,
    required this.video,
    required this.onTap,
  }) : super(key: key);

  final Video video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: AppRadius.control + 2,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          UserAvatar(url: video.owner.face, name: video.owner.name, size: 42),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  video.owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('UID ${video.owner.mid}',
                    style: TextStyle(fontSize: 11, color: sub)),
              ],
            ),
          ),
          if (video.owner.mid.isNotEmpty)
            GlassChip(
              label: '查看主页',
              icon: Icons.person_outline_rounded,
              tint: AppColors.pink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelStyle: const TextStyle(fontSize: 12),
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

/// 四连互动栏：点赞 / 投币 / 收藏 / 分享。
class DetailInteractionBar extends StatelessWidget {
  const DetailInteractionBar({
    Key? key,
    required this.controller,
    required this.video,
  }) : super(key: key);

  final DetailController controller;
  final Video video;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final favorite = library.isFavorite(video.bvid);
        final later = library.inWatchLater(video.bvid);
        return Row(
          children: <Widget>[
            DetailInteractionItem(
              icon: Icons.thumb_up_off_alt_outlined,
              label: '点赞',
              value: video.stat.like,
              onTap: () => openExternal(context, video.webUrl),
            ),
            DetailInteractionItem(
              icon: Icons.monetization_on_outlined,
              label: '投币',
              value: video.stat.coin,
              onTap: () => openExternal(context, video.webUrl),
            ),
            DetailInteractionItem(
              icon: favorite ? Icons.star_rounded : Icons.star_border_rounded,
              label: '收藏',
              value: video.stat.favorite,
              active: favorite,
              onTap: () => library.toggle(LibraryKind.favorites, video),
            ),
            DetailInteractionItem(
              icon: Icons.share_outlined,
              label: '分享',
              value: video.stat.share,
              onTap: () => showVideoShareSheet(
                context,
                video: video,
                onOpenExternal: (String url) => openExternal(context, url),
              ),
            ),
            const Spacer(),
            GlassChip(
              label: later ? '已在稍后再看' : '稍后再看',
              icon: Icons.watch_later_outlined,
              selected: later,
              tint: AppColors.pink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              labelStyle: const TextStyle(fontSize: 12),
              onTap: () => library.toggle(LibraryKind.watchLater, video),
            ),
          ],
        );
      },
    );
  }
}

/// 互动栏里的单个条目：图标 + 数值。
class DetailInteractionItem extends StatelessWidget {
  const DetailInteractionItem({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.active = false,
  }) : super(key: key);

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 21,
                color: active ? AppColors.pink : context.primaryTextColor,
              ),
              const SizedBox(height: 4),
              Text(
                Fmt.compact(value),
                style: TextStyle(
                  fontSize: 10.5,
                  color: active ? AppColors.pink : sub,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 简介卡片：全文展示，不再折叠、不再显示展开按钮。
class DetailDescriptionCard extends StatelessWidget {
  const DetailDescriptionCard({Key? key, required this.controller})
      : super(key: key);

  final DetailController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: AppRadius.control + 2,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('简介',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            controller.desc,
            style: TextStyle(
                fontSize: 13, height: 1.6, color: context.subTextColor),
          ),
        ],
      ),
    );
  }
}

/// 单个统计指标：图标 + 数值。
class DetailStat extends StatelessWidget {
  const DetailStat(this.icon, this.value, this.label, {Key? key})
      : super(key: key);

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppTextColor.tertiary(context)),
          const SizedBox(width: 4),
          Text(
            Fmt.compact(value),
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w600,
              color: AppTextColor.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailSortChip extends StatelessWidget {
  const DetailSortChip({
    Key? key,
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  }) : super(key: key);

  final String label;
  final int value;
  final int current;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      labelStyle: const TextStyle(fontSize: 11.5),
      onTap: () => onTap(value),
    );
  }
}

class DetailCommentCard extends StatelessWidget {
  const DetailCommentCard({Key? key, required this.comment}) : super(key: key);

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UserAvatar(url: comment.avatar, name: comment.uname, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(comment.uname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pink)),
                      ),
                      if (comment.isTop) ...<Widget>[
                        const SizedBox(width: 6),
                        GlassPill(
                          radius: 4,
                          tint: AppColors.pink.withOpacity(0.18),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          child: const Text('置顶',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.pink,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      const Spacer(),
                      Text(Fmt.relative(comment.ctime),
                          style: TextStyle(fontSize: 10.5, color: sub)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(comment.message,
                      style: const TextStyle(fontSize: 13, height: 1.55)),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Icon(Icons.thumb_up_off_alt_outlined,
                          size: 12, color: sub),
                      const SizedBox(width: 3),
                      Text(Fmt.compact(comment.like),
                          style: TextStyle(fontSize: 10.5, color: sub)),
                      if (comment.replyCount > 0) ...<Widget>[
                        const SizedBox(width: 14),
                        Text('${Fmt.compact(comment.replyCount)} 条回复',
                            style: TextStyle(fontSize: 10.5, color: sub)),
                      ],
                      if (comment.location.isNotEmpty) ...<Widget>[
                        const Spacer(),
                        Text(comment.location,
                            style: TextStyle(fontSize: 10.5, color: sub)),
                      ],
                    ],
                  ),
                  if (comment.replies.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: GlassPanel(
                        radius: 12,
                        padding: const EdgeInsets.all(9),
                        showSheen: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: comment.replies
                              .map((r) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                            fontSize: 11.5, color: sub),
                                        children: <TextSpan>[
                                          TextSpan(
                                              text: '${r.uname}：',
                                              style: const TextStyle(
                                                  color: AppColors.blue)),
                                          TextSpan(text: r.message),
                                        ],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
