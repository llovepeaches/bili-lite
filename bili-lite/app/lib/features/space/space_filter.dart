import '../../data/models.dart';

/// 从站内搜索结果里挑出确实属于该 UP 主的稿件。
///
/// 「查看主页」改成应用内打开后，稿件来自按 UP 主名称做的站内搜索，
/// 结果里会混入同名 UP 主、转载与二创。只保留 `owner.mid` 完全一致的条目，
/// 不把别人的视频冒充成该 UP 主的作品；mid 为空时直接返回空列表。
List<Video> filterOwnerVideos(List<Video> source, String mid) {
  if (mid.isEmpty) return const <Video>[];
  return source
      .where((Video v) => v.owner.mid == mid)
      .toList(growable: false);
}
