import 'package:flutter/material.dart';

/// 数字 / 时间 / 时长的展示格式化。UI 层的细节都收敛在这里。
class Fmt {
  Fmt._();

  /// 12345 → 1.2万，123456789 → 1.2亿
  static String compact(int value) {
    if (value < 0) return '0';
    if (value < 10000) return '$value';
    if (value < 100000000) {
      return '${_oneDecimal(value / 10000)}万';
    }
    return '${_oneDecimal(value / 100000000)}亿';
  }

  static String _oneDecimal(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// 秒 → 01:14 / 1:02:03
  static String duration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  /// Unix 秒 → 相对时间 / 日期
  static String relative(int unixSeconds, [int? nowSeconds]) {
    if (unixSeconds <= 0) return '';
    final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - unixSeconds;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60}分钟前';
    if (diff < 86400) return '${diff ~/ 3600}小时前';
    if (diff < 86400 * 7) return '${diff ~/ 86400}天前';
    final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String fullDate(int unixSeconds) {
    if (unixSeconds <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String sourceLabel(String source) {
    switch (source) {
      case 'live':
        return '实时';
      case 'cache':
        return '缓存';
      case 'mock':
        return '离线';
      case 'static':
        return '静态';
      default:
        return source.isEmpty ? '' : source;
    }
  }

  static Color sourceColor(String source, bool dark) {
    switch (source) {
      case 'live':
        return const Color(0xFF34B27B);
      case 'cache':
        return const Color(0xFFE9A23B);
      case 'mock':
        return const Color(0xFF8B8F98);
      default:
        return const Color(0xFF8B8F98);
    }
  }
}
