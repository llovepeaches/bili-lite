/// 应用版本单一真源（自 v0.1.0 起）。
///
/// 规则：**每次发版只改这里 + `pubspec.yaml`**，其余全部派生：
///   * `pubspec.yaml` 的 `version` 必须等于 `kAppVersion+kAppBuildNumber`
///   * CI 的 `release_tag` 必须等于 `kReleaseTag`（由版本号自动派生）
///   * 设置页「App 版本」「发布标记」「更新检查」都读这里的常量
///
/// CI 的 `Verify version sync` 步骤会逐项比对，任一处不一致直接让构建失败，
/// 避免再次出现「设置页写死 1.4.0 / pubspec 1.6.0 / tag v1.6.0」三处漂移。
const String kAppVersion = '0.1.5';
const int kAppBuildNumber = 6;

/// 用户可见版本串：只显示 `major.minor.patch`。
///
/// `kAppBuildNumber` 仍保留给 `pubspec.yaml`、原生 versionCode 与 CI 校验使用，
/// 但不再拼到应用内展示文本里——从 v0.1.4 起用户侧统一不显示 `+构建号`。
const String kAppVersionLabel = kAppVersion;

/// 发布 tag 前缀。更新检查只识别这个前缀，历史 tag 不会误报。
const String kReleaseTagPrefix = 'bili-lite-v';
const String kReleaseTag = '$kReleaseTagPrefix$kAppVersion';

const String kRepoOwner = 'llovepeaches';
const String kRepoName = 'bili-lite';
const String kReleasesLatestApi =
    'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest';
const String kReleasesPage =
    'https://github.com/$kRepoOwner/$kRepoName/releases';

/// 解析 `major.minor.patch`（允许带 `+build` 或 `v` 前缀）。失败返回 null。
List<int>? _parseSemver(String input) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(input.trim());
  if (m == null) return null;
  return <int>[int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}

/// 语义化版本比较：`a > b` 返回 1，相等返回 0，`a < b` 返回 -1。
/// 任一无法解析返回 null，由调用方决定如何降级（绝不把解析失败当成「有更新」）。
int? compareSemver(String a, String b) {
  final pa = _parseSemver(a);
  final pb = _parseSemver(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] > pb[i] ? 1 : -1;
  }
  return 0;
}

/// `bili-lite-v0.2.0` → `0.2.0`；前缀不符或版本号非法返回 null。
String? versionFromTag(String tag) {
  final t = tag.trim();
  if (!t.startsWith(kReleaseTagPrefix)) return null;
  final v = t.substring(kReleaseTagPrefix.length);
  return _parseSemver(v) == null ? null : v;
}
