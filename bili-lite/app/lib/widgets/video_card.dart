import 'package:flutter/material.dart';

import '../core/card_style.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/models.dart';
import 'cover_image.dart';
import 'glass.dart';
import 'glass_text.dart';

/// 自适应网格里的扁平视频卡片。窄屏 2 列、桌面 5 列共用同一个组件。
///
/// 两种样式（见 [CardStyle]）：
///   * [CardStyle.immersive] —— 弹幕数叠在封面左下角，与时长左右呼应，
///     封面下方只留标题 / UP 主 / 播放量三行，一屏能看更多内容。
///   * [CardStyle.compact] —— 统计信息全部排在封面下方，文字更易读。
///
/// ## 本轮（第十八轮）调整
///
/// 上一版的卡片信息排布有几个具体问题（见 `docs/preview/50-r7-home.png`）：
///   * 统计行是「播放量 · 弹幕 … 时间戳」的**两端对齐**布局，导致同屏
///     多张卡片的数字左右乱跳，扫读时没有一条稳定的竖向基线；
///   * 标题字号 13.5、UP 主名 11.5、时间戳 10.5 三级各差 1~2px，
///     但都是「灰色小字」，层级拉不开；
///   * 标题压在近全透的玻璃上，靠光晕补丁保证可读，在彩色封面上会显脏。
///
/// 现在改成：统计行统一左对齐成一条基线；字号全部改用 [AppFontSize] 的
/// 语义命名；卡片改为实色容器，标题直接用主题文字色，不再逐处写光晕。
class VideoCard extends StatefulWidget {
  const VideoCard({
    Key? key,
    required this.video,
    required this.onTap,
    this.rank = 0,
    this.onLongPress,
    this.style = CardStyle.immersive,
  }) : super(key: key);

  final Video video;
  final VoidCallback onTap;
  final int rank;
  final VoidCallback? onLongPress;
  final CardStyle style;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // 按下只影响外层装饰。卡片内容（封面、标题、统计）拆到独立
    // widget 里，避免鼠标划过一屏卡片时把上百棵子树重建一遍。
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
          transform: Matrix4.identity()..scale(_pressed ? 0.975 : 1.0),
          child: _VideoCardContent(
            video: widget.video,
            rank: widget.rank,
            elevated: _hover,
            style: widget.style,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
          ),
        ),
      ),
    );
  }
}

/// 卡片内容层。与外层装饰分离，hover / pressed 变化不再重建它。
class _VideoCardContent extends StatelessWidget {
  const _VideoCardContent({
    required this.video,
    required this.rank,
    required this.elevated,
    required this.style,
    required this.onTap,
    this.onLongPress,
  });

  final Video video;
  final int rank;
  final bool elevated;
  final CardStyle style;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final immersive = style == CardStyle.immersive;

    return GlassPanel(
      radius: AppRadius.panel,
      padding: const EdgeInsets.all(8),
      elevated: elevated,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                    child: CoverImage(url: video.cover, radius: 14)),
                // 沉浸式：弹幕数与时长左右呼应，都压在封面底边。
                if (immersive && video.stat.danmaku > 0)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _OverlayBadge(
                      icon: Icons.subtitles_outlined,
                      text: Fmt.compact(video.stat.danmaku),
                    ),
                  ),
                if (video.durationText.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: GlassPill(
                      radius: AppRadius.pill,
                      onDark: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        video.durationText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppFontSize.overlay,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                if (rank > 0)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _RankPill(rank: rank),
                  )
                else if (video.reason.isNotEmpty)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: GlassPill(
                      radius: AppRadius.pill,
                      tint: AppColors.pink,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        video.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppFontSize.overlay,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: immersive ? 7 : 8),
          // 标题用 AppTextStyles.cardTitle，层级与全 App 一致；
          // 在近全透玻璃上的可读性交给 GlassText 处理。
          GlassText(
            video.title.isEmpty ? '（无标题）' : video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.cardTitle(context),
          ),
          SizedBox(height: immersive ? 6 : 7),
          // UP 主行：头像 + 名字
          Row(
            children: <Widget>[
              UserAvatar(
                  url: video.owner.face, name: video.owner.name, size: 16),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  video.owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.meta(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 统计行：统一左对齐成一条基线。
          //
          // 上一版是「播放量在左、时间戳在右」的两端对齐，同屏多张卡片的
          // 数字会左右乱跳。现在全部靠左、用固定间距分隔，形成一条稳定的
          // 竖向阅读基线 —— 扫读时眼睛只需沿一条线走。
          Row(
            children: <Widget>[
              _MiniStat(
                  icon: Icons.play_circle_outline,
                  text: Fmt.compact(video.stat.view)),
              // 紧凑式才把弹幕数排在文字行；沉浸式已经叠在封面上了。
              if (!immersive) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                _MiniStat(
                    icon: Icons.subtitles_outlined,
                    text: Fmt.compact(video.stat.danmaku)),
              ],
              if (video.pubdate > 0) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                // 用「·」分隔而不是靠右对齐，视觉上更轻。
                Text('·', style: AppTextStyles.caption(context)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  Fmt.relative(video.pubdate),
                  style: AppTextStyles.caption(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 压在封面上的信息徽标（弹幕数等）。
class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF18191C),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: AppFontSize.overlay,
                fontWeight: FontWeight.w600),
          ),
        ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: AppTextColor.tertiary(context)),
        const SizedBox(width: 3),
        Text(text, style: AppTextStyles.caption(context)),
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
      radius: AppRadius.pill,
      tint: highlight ? AppColors.pink : null,
      onDark: !highlight,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        '$rank',
        style: const TextStyle(
            color: Colors.white,
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800),
      ),
    );
  }
}
