import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// 统一封面组件：走 BFF 图片代理、带加载占位与失败兜底。
class CoverImage extends StatelessWidget {
  const CoverImage({
    Key? key,
    required this.url,
    this.radius = 10,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  final String url;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = _placeholder(dark);

    if (url.isEmpty) return ClipRRect(borderRadius: BorderRadius.circular(radius), child: placeholder);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        ApiConfig.image(url),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 480,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.pink.withOpacity(0.65)),
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
              ),
            ],
          );
        },
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }

  Widget _placeholder(bool dark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[Color(0xFF3A4055), Color(0xFF222636), Color(0xFF332941)]
              : const <Color>[Color(0xFFFFFFFF), Color(0xFFEEF1FA), Color(0xFFFCEFF5)],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white.withOpacity(dark ? 0.10 : 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.image_outlined,
              size: 26,
              color: dark ? Colors.white24 : Colors.black12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆形头像，URL 为空时用昵称首字兜底
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    Key? key,
    required this.url,
    required this.name,
    this.size = 22,
  }) : super(key: key);

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.pink.withOpacity(0.16),
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1),
          style: TextStyle(
              color: AppColors.pink, fontSize: size * 0.45, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withOpacity(dark ? 0.28 : 0.9),
            Colors.white.withOpacity(dark ? 0.04 : 0.2),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: dark
                  ? Colors.black.withOpacity(0.35)
                  : const Color(0xFF66588C).withOpacity(0.18),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(0.9),
      child: ClipOval(
        child: Image.network(
          ApiConfig.image(url),
          width: size - 1.8,
          height: size - 1.8,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => CircleAvatar(
            radius: (size - 1.8) / 2,
            backgroundColor: dark ? const Color(0xFF2A2C31) : const Color(0xFFECEEF1),
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1),
              style: TextStyle(fontSize: size * 0.45, color: AppColors.pink),
            ),
          ),
        ),
      ),
    );
  }
}
