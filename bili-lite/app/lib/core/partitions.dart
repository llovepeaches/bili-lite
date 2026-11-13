import 'package:flutter/material.dart';

import '../data/models.dart';

/// B 站分区表（排行榜 rid）。
///
/// 重构前这份数据存在三处且互不一致：
///   * `state/app_state.dart` 的 `_partitions`  —— 12 项，缺国创 / 舞蹈 / 汽车等
///   * `data/api_client.dart` 的 `_partitions`  —— 21 项
///   * `server/src/index.js` 的 PARTITIONS      —— 21 项
///
/// 结果是：离线模式（走 app_state 的兜底）与在线模式（走服务端 meta）
/// 显示的分区数量不同，排行榜频道的分区条会在两种模式下悄悄变化。
///
/// 现在收敛为单一数据源，客户端与服务端保持同序同项。
class BiliPartitions {
  BiliPartitions._();

  /// 分区定义，顺序即 UI 展示顺序。
  static const List<Partition> items = <Partition>[
    Partition(rid: 0, name: '全站'),
    Partition(rid: 1, name: '动画'),
    Partition(rid: 168, name: '国创'),
    Partition(rid: 3, name: '音乐'),
    Partition(rid: 129, name: '舞蹈'),
    Partition(rid: 4, name: '游戏'),
    Partition(rid: 36, name: '知识'),
    Partition(rid: 188, name: '科技'),
    Partition(rid: 234, name: '运动'),
    Partition(rid: 223, name: '汽车'),
    Partition(rid: 160, name: '生活'),
    Partition(rid: 211, name: '美食'),
    Partition(rid: 217, name: '动物圈'),
    Partition(rid: 119, name: '鬼畜'),
    Partition(rid: 155, name: '时尚'),
    Partition(rid: 202, name: '资讯'),
    Partition(rid: 5, name: '娱乐'),
    Partition(rid: 181, name: '影视'),
    Partition(rid: 177, name: '纪录片'),
    Partition(rid: 23, name: '电影'),
    Partition(rid: 11, name: '电视剧'),
  ];

  /// 名字查表，用于「XX 排行榜」标题。
  static String nameOf(int rid) {
    for (final item in items) {
      if (item.rid == rid) return item.name;
    }
    return '分区';
  }

  /// 分区图标与配色。
  ///
  /// 21 个分区只靠文字很难一眼分辨，MiniBili 用「图标 + 名称」的浮层菜单
  /// 解决这个问题。这里用 Material 图标实现同样的识别度。
  ///
  /// 为什么不用 emoji：emoji 依赖系统字体，桌面 Web 与部分 Linux 环境缺字形时
  /// 会渲染成豆腐块；Material 图标随 Flutter 走，全端一致。
  static const Map<int, IconData> _icons = <int, IconData>{
    0: Icons.public, // 全站
    1: Icons.animation, // 动画
    168: Icons.flag_outlined, // 国创
    3: Icons.music_note_rounded, // 音乐
    129: Icons.directions_walk_rounded, // 舞蹈
    4: Icons.sports_esports_rounded, // 游戏
    36: Icons.menu_book_rounded, // 知识
    188: Icons.memory_rounded, // 科技
    234: Icons.sports_soccer_rounded, // 运动
    223: Icons.directions_car_filled_rounded, // 汽车
    160: Icons.home_work_rounded, // 生活
    211: Icons.restaurant_rounded, // 美食
    217: Icons.pets_rounded, // 动物圈
    119: Icons.emoji_emotions_rounded, // 鬼畜
    155: Icons.checkroom_rounded, // 时尚
    202: Icons.newspaper_rounded, // 资讯
    5: Icons.theater_comedy_rounded, // 娱乐
    181: Icons.movie_filter_rounded, // 影视
    177: Icons.travel_explore_rounded, // 纪录片
    23: Icons.local_movies_rounded, // 电影
    11: Icons.live_tv_rounded, // 电视剧
  };

  /// 分区对应的主色，用于图标着色与选中态。
  static const Map<int, Color> _colors = <int, Color>{
    0: Color(0xFF6B7CFF),
    1: Color(0xFFFF7BAC),
    168: Color(0xFFE85D75),
    3: Color(0xFF38C7B0),
    129: Color(0xFFFF6FA5),
    4: Color(0xFF7C6BFF),
    36: Color(0xFF4AA3FF),
    188: Color(0xFF39C0ED),
    234: Color(0xFF52C41A),
    223: Color(0xFF5B8FF9),
    160: Color(0xFFFFA940),
    211: Color(0xFFFF8C42),
    217: Color(0xFFB37FEB),
    119: Color(0xFF9C6ADE),
    155: Color(0xFFEB6FA5),
    202: Color(0xFF4B8CFF),
    5: Color(0xFFFFB100),
    181: Color(0xFF9B5DE5),
    177: Color(0xFF2BA9A9),
    23: Color(0xFFE05252),
    11: Color(0xFF3E7BFA),
  };

  /// 分区对应的 Material 图标。未登记的分区回落到通用图标。
  static IconData iconOf(int rid) => _icons[rid] ?? Icons.folder_rounded;

  /// 分区对应的主色。未登记的分区回落到主题粉。
  static Color colorOf(int rid) => _colors[rid] ?? const Color(0xFFFF6699);
}
