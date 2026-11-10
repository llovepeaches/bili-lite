// Web 端：用官方站外播放器 iframe 承载播放，内容始终来自 player.bilibili.com。
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

int _viewSeq = 0;

/// 返回官方播放器的平台视图；App 不解析视频源、不读取 iframe 内部状态。
Widget? buildOfficialPlayer(String url) {
  final viewType = 'bili-official-player-${_viewSeq++}';
  // ignore: undefined_prefixed_name
  ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final frame = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('allow',
          'autoplay; encrypted-media; picture-in-picture; fullscreen')
      ..setAttribute('allowfullscreen', 'true')
      ..setAttribute('loading', 'lazy')
      ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
    return frame;
  });
  return HtmlElementView(viewType: viewType);
}
