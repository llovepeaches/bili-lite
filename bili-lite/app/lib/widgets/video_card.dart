import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/glass_theme.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'cover_image.dart';
import 'glass.dart';

/// 自适应网格里的玻璃视频卡片。窄屏 2 列、桌面 5 列共用同一个组件。
class VideoCard extends StatefulWidget {
  const VideoCard({
    Key? key,
    required this.video,
    required this.onTap,
    this.rank = 0,
    this.onLongPress,
  }) : super(key: key);

  final Video video;
  final VoidCallback onTap;
  final int rank;
  final VoidCallback? onLongPress;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.darkSub : AppColors.lightSub;
    final glass = GlassTheme.of(context).enabled;
    final video = widget.video;

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(0.0, glass && _hover && !_pressed ? -4.0 : 0.0)
            ..scale(_pressed ? 0.975 : 1.0),
          child: GlassPanel(
            radius: 22,
            padding: const EdgeInsets.all(8),
            // 内容让位：卡片内部几乎全透，只留一圈折射亮边，让封面成为主体。
            fillScale: 0.50,
            elevated: _hover,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: CoverImage(url: video.cover, radius: 14)),
                      // 封面底部一层很淡的玻璃反光
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  Colors.white.withOpacity(glass ? 0.10 : 0),
                                  Colors.transparent,
                                  Colors.white.withOpacity(glass ? 0.06 : 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (video.durationText.isNotEmpty)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: GlassPill(
                            radius: 999,
                            onDark: true,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              video.durationText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      if (widget.rank > 0)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _RankPill(rank: widget.rank),
                        )
                      else if (video.reason.isNotEmpty)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: GlassPill(
                            radius: 999,
                            tint: AppColors.pink,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              video.reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  video.title.isEmpty ? '（无标题）' : video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: dark ? AppColors.darkText : AppColors.lightText,
                    // 近乎全透的玻璃上给标题一层极淡光晕，保证任何背景都可读。
                    shadows: glass
                        ? <Shadow>[
                            Shadow(
                              color: dark
                                  ? Colors.black.withOpacity(0.55)
                                  : Colors.white.withOpacity(0.90),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    UserAvatar(url: video.owner.face, name: video.owner.name, size: 17),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        video.owner.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: sub),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    _MiniStat(
                        icon: Icons.play_circle_outline,
                        text: Fmt.compact(video.stat.view)),
                    const SizedBox(width: 8),
                    _MiniStat(
                        icon: Icons.subtitles_outlined,
                        text: Fmt.compact(video.stat.danmaku)),
                    const Spacer(),
                    if (video.pubdate > 0)
                      Text(
                        Fmt.relative(video.pubdate),
                        style: TextStyle(fontSize: 10.5, color: sub),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSub
        : AppColors.lightSub;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: sub),
        const SizedBox(width: 2),
        Text(text, style: TextStyle(fontSize: 10.5, color: sub)),
      ],
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final highlight = rank <= 3;
    return GlassPill(
      radius: 999,
      tint: highlight ? AppColors.pink : null,
      onDark: !highlight,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        '$rank',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
