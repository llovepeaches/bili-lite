import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tokens.dart';

/// 在系统浏览器里打开外链；打不开时复制链接兜底。
///
/// 详情页的「原站」「分享」「投币」等多处都要跳外链，抽成顶层函数后
/// 兜底提示只有一份，不会出现一处复制了链接、另一处静默失败。
Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  bool opened = false;
  try {
    if (await canLaunchUrl(uri)) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已复制链接，可粘贴到浏览器打开'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sheet)),
      ),
    );
  }
}
