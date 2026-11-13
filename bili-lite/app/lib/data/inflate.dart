/// 解压工具的条件导出。
///
/// B 站弹幕接口返回的是 deflate(raw) 压缩的 XML，需要解压才能解析。
/// `dart:io` 的 `ZLibDecoder` 在 Web 端不存在，所以用条件导入分离：
///   * 原生端 → [inflate_io.dart]，用 `ZLibDecoder(raw: true)`；
///   * Web 端 → [inflate_stub.dart]，直接抛错（Web 端走 BFF，服务端已解压）。
export 'inflate_stub.dart' if (dart.library.io) 'inflate_io.dart';
