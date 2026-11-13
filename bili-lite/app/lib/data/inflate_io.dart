import 'dart:io';

/// 解压 deflate(raw) 数据。
///
/// B 站弹幕接口 `/x/v1/dm/list.so` 返回的就是 deflate(raw) 压缩的 XML。
/// Dart 的 `ZLibDecoder` 默认按 zlib 包装解析，这里必须显式 `raw: true`。
String inflateRawToString(List<int> bytes) {
  final List<int> out = ZLibDecoder(raw: true).convert(bytes);
  return String.fromCharCodes(out);
}
