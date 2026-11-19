import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../core/tokens.dart';

/// 统一封面组件：走 BFF 图片代理、带加载占位与失败兜底。
///
/// 扁平化后占位图与头像边框都是实色，不再有渐变、半透明叠层或阴影。
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
    final dark = context.isDark;
    final placeholder = _placeholder(dark);

    if (url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: placeholder,
      );
    }

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
            children: <Widget>[
              placeholder,
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
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
      color: dark ? const Color(0xFF24262B) : const Color(0xFFF1F1F3),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 26,
          color: dark ? AppColors.darkLine : AppColors.lightLine,
        ),
      ),
    );
  }
}

/// 圆形头像，URL 为空时用昵称首字兜底。
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
    final dark = context.isDark;
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.pinkSoft,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1),
        style: const TextStyle(
          color: Color(0xFF18191C),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (url.isEmpty) return fallback;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: dark ? AppColors.darkLine : AppColors.lightLine,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: ClipOval(
        child: Image.network(
          ApiConfig.image(url),
          width: size - 2,
          height: size - 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
