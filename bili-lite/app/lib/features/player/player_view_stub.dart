import 'package:flutter/material.dart';

/// 当前平台能否在应用内直接承载官方播放器。
///
/// 原生六端在 Flutter 3.0 下没有统一的 WebView 插件，只能降级为系统浏览器。
/// 该常量与 web 端 `player_view_web.dart` 中的同名常量对称，
/// 由 `player_view.dart` 条件导出，业务代码无需关心当前编译平台。
const bool kCanEmbedOfficialPlayer = false;

/// 原生端占位：不伪造播放器、不解析播放地址。
/// 返回 null 后由 PlayerPage 显示官方播放器入口（同一个官方 URL）。
Widget? buildOfficialPlayer(String url) => null;
