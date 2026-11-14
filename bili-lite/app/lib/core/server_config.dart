import '../core/storage.dart';

/// 用户可运行时修改的授权服务地址。
///
/// 为什么需要它：`String.fromEnvironment('BFF_URL')` 是**编译期**常量，
/// APK 一旦打出就改不了。而 Android 默认的 `10.0.2.2` 只是模拟器指向宿主机
/// 的别名，真机上永远连不上——这正是「授权服务不可用」的直接原因。
///
/// 现在主登录走扫码（全 HTTPS、不需要任何服务），这里只服务官方 OAuth
/// 备用通道：用户可以在真机上填自己电脑的局域网地址或已部署的 https 域名，
/// 立即生效并持久化到本机，不需要重新打包。
class ServerConfig {
  ServerConfig._();

  static final ServerConfig instance = ServerConfig._();

  static const String _kKey = 'bili_lite_bff_url';

  String _value = '';

  String get value => _value;
  bool get hasCustom => _value.trim().isNotEmpty;

  Future<void> init() async {
    await LocalStore.instance.init();
    _value = LocalStore.instance.getString(_kKey) ?? '';
  }

  /// 规范化并保存。空串表示恢复编译期默认。
  Future<String> set(String raw) async {
    var value = raw.trim();
    if (value.isNotEmpty) {
      // 去掉末尾斜杠，避免拼出 `//api/...`
      while (value.endsWith('/') && value.length > 8) {
        value = value.substring(0, value.length - 1);
      }
      if (!value.startsWith('http://') && !value.startsWith('https://')) {
        value = 'http://$value';
      }
    }
    _value = value;
    await LocalStore.instance.setString(_kKey, value);
    return value;
  }

  Future<void> clear() async {
    _value = '';
    await LocalStore.instance.remove(_kKey);
  }

  /// 基本校验：必须是 http/https 且有主机名。返回错误文案，合法时返回空串。
  static String? validate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    // 显式写了协议但不是 http/https 的，直接拒绝；否则下面的自动补协议
    // 会把 `ftp://1.2.3.4` 拼成 `http://ftp://1.2.3.4` 蒙混过关。
    final schemeEnd = value.indexOf('://');
    if (schemeEnd > 0) {
      final scheme = value.substring(0, schemeEnd);
      if (scheme != 'http' && scheme != 'https') {
        return '只支持 http / https 地址';
      }
    }
    final withScheme = value.startsWith('http://') ||
            value.startsWith('https://')
        ? value
        : 'http://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || uri.scheme.isEmpty) {
      return '地址格式不正确，例如 http://192.168.1.10:8787';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '只支持 http / https 地址';
    }
    return null;
  }
}
