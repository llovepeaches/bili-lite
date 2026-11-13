import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';

/// 统一的确认对话框。
///
/// 重构前这个「取消 / 确认（粉色）」的 AlertDialog 在四个文件里各抄了一遍：
/// `library_page.dart` 的 `_confirmClear` 与 `_confirmRemove`、
/// `settings_page.dart` 的 `_clearAll`、`account_card.dart` 的 `_signOut`。
/// 除了文案和回调，四段的圆角、按钮样式、文本样式完全一致——改一次样式要改四处。
///
/// 现在统一走这里，各处只提供文案与回调。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(primary: AppColors.pink),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
