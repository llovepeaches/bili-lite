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
}
