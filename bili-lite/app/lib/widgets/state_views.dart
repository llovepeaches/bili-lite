import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/glass_theme.dart';
import '../core/theme.dart';
import 'glass.dart';

/// 数据来源小标签：实时 / 缓存 / 离线，让第三方客户端的数据状态透明。
class SourceBadge extends StatelessWidget {
  const SourceBadge({Key? key, required this.source, this.stale = false})
      : super(key: key);

  final String source;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    if (source.isEmpty || source == 'static' || source == 'empty') {
      return const SizedBox.shrink();
    }
    final color = Fmt.sourceColor(
        source, Theme.of(context).brightness == Brightness.dark);
    return GlassPill(
      radius: 7,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(color: color.withOpacity(0.7), blurRadius: 5),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            stale ? '${Fmt.sourceLabel(source)}·陈旧' : Fmt.sourceLabel(source),
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class LoadingGrid extends StatelessWidget {
  const LoadingGrid({Key? key, required this.columns, this.itemCount = 8})
      : super(key: key);

  final int columns;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

/// 玻璃骨架卡片：模拟封面 + 两行标题 + 一行数据的位置。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(8),
      showSheen: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          Expanded(child: _Block(radius: 12)),
          SizedBox(height: 8),
          _Block(height: 12, radius: 4),
          SizedBox(height: 5),
          _Block(width: 0.72, height: 12, radius: 4),
          SizedBox(height: 9),
          _Block(width: 0.46, height: 9, radius: 4),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, this.height, this.radius = 6});

  /// 宽度：null 表示撑满；0~1 表示占父宽度的比例。
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final enabled = GlassTheme.of(context).enabled;
    return FractionallySizedBox(
      widthFactor: width != null && width! > 0 && width! <= 1 ? width : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    p.dark
                        ? Colors.white.withOpacity(0.13)
                        : Colors.white.withOpacity(0.72),
                    p.dark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFDDE2F0).withOpacity(0.55),
                  ],
                )
              : null,
          color: enabled
              ? null
              : (p.dark ? const Color(0xFF24262B) : const Color(0xFFE9EBEF)),
          border: enabled
              ? Border.all(color: p.dark ? Colors.white10 : Colors.white70)
              : null,
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    Key? key,
    required this.message,
    required this.onRetry,
    this.compact = false,
  }) : super(key: key);

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSub
        : AppColors.lightSub;
    return Center(
      child: GlassPanel(
        radius: 22,
        padding: EdgeInsets.symmetric(
            horizontal: 24, vertical: compact ? 24 : 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: compact ? 32 : 44, color: sub),
            const SizedBox(height: 12),
            const Text('数据没取到',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: sub, height: 1.5),
            ),
            const SizedBox(height: 16),
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

class EmptyView extends StatelessWidget {
  const EmptyView({
    Key? key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.action,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSub
        : AppColors.lightSub;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GlassPanel(
              radius: 22,
              padding: const EdgeInsets.all(17),
              tint: AppColors.pink,
              child: Icon(icon, size: 30, color: AppColors.pink),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: sub, height: 1.5)),
            ],
            if (action != null) ...<Widget>[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// 带发光玻璃竖条的小节标题
class SectionTitle extends StatelessWidget {
  const SectionTitle({Key? key, required this.title, this.trailing})
      : super(key: key);

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // mainAxisSize.min：在 Column（无界宽度约束）和 Row 里都不会因 Spacer 报错
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const GlassAccent(),
          const SizedBox(width: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
