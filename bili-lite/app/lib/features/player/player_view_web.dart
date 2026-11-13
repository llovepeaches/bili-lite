// Web 端：用官方站外播放器 iframe 承载播放，内容始终来自 player.bilibili.com。
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

int _viewSeq = 0;

/// 当前平台能否在应用内直接承载官方播放器。
///
/// 重构前这个能力判断写在 `core/bili_player.dart` 的 `BiliPlayer.canEmbed`
/// 里，而实际的承载实现分散在 web / stub 两个文件里——同一件事有两个真相来源，
/// 改一处忘另一处就会出现「声称能内嵌、实际返回 null」的错位。
/// 现在能力标记与实现放在同一个平台文件里，不再重复。
const bool kCanEmbedOfficialPlayer = true;

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
