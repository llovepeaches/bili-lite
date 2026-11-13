/// 视频卡片的呈现样式。
///
/// 借鉴 MiniBili 的双样式设计：沉浸式把弹幕数叠在封面上（信息密度高、
/// 一屏能看更多内容），紧凑式把统计信息排在封面下方（文字更易读）。
///
/// 放在 core 而不是 state：这个枚举同时被布局计算（core/responsive.dart）
/// 与用户偏好（state/preferences.dart）使用，放 core 才不会让 core 反向
/// 依赖 state。
enum CardStyle {
  immersive('沉浸式', '弹幕数叠在封面上'),
  compact('紧凑型', '统计信息排在封面下方');

  const CardStyle(this.label, this.hint);

  final String label;
  final String hint;

  String get key => name;

  static CardStyle fromKey(String key) => CardStyle.values.firstWhere(
      (e) => e.key == key,
      orElse: () => CardStyle.immersive);
}
