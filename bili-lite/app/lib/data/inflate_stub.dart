/// Web 端的解压占位实现。
///
/// Web 端弹幕数据来自 BFF（服务端已经解压并解析成 JSON），
/// 原生端直连才会真正调用解压函数，所以这里只需要给出一个明确的错误。
String inflateRawToString(List<int> bytes) {
  throw UnsupportedError('Web 端不支持本地解压，弹幕请走 BFF');
}
