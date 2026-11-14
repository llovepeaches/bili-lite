import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/server_config.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';

/// 官方 OAuth 备用通道的「授权服务地址」设置。
///
/// 真机上 `10.0.2.2` 只是 Android 模拟器指向宿主机的别名，永远连不上；
/// 而 APK 里的 `String.fromEnvironment('BFF_URL')` 是编译期常量改不了。
/// 这个卡片让用户可以在 App 里直接填局域网 IP / https 域名并立即生效。
class ServerConfigCard extends StatefulWidget {
  const ServerConfigCard({Key? key}) : super(key: key);

  @override
  State<ServerConfigCard> createState() => _ServerConfigCardState();
}

class _ServerConfigCardState extends State<ServerConfigCard> {
  late final TextEditingController _input;
  String _error = '';
  String _saved = '';

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: ServerConfig.instance.value);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = ServerConfig.validate(_input.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final value = await ServerConfig.instance.set(_input.text);
    setState(() {
      _error = '';
      _saved = value.isEmpty ? '已恢复默认地址' : '已保存：$value';
      _input.text = value;
    });
    // 地址变了，让官方 OAuth 通道立刻重新探活。
    await authSession.refreshConfig();
  }

  Future<void> _clear() async {
    await ServerConfig.instance.clear();
    _input.clear();
    setState(() {
      _error = '';
      _saved = '已恢复默认地址';
    });
    await authSession.refreshConfig();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(title: '授权服务地址（可选）'),
          const SizedBox(height: 8),
          Text(
            '只有下方「官方 OAuth」备用通道才需要它。'
            '真机上 10.0.2.2 是模拟器专用地址，请填电脑的局域网 IP'
            '（手机与电脑连同一 WiFi）或已部署的 https 域名。'
            '扫码登录不需要这一项。',
            style: TextStyle(fontSize: 11.5, height: 1.65, color: sub),
          ),
          const SizedBox(height: 10),
          _kv('当前生效', ApiConfig.oauthDisplayBase, sub),
          const SizedBox(height: 10),
          TextField(
            controller: _input,
            decoration: InputDecoration(
              labelText: 'BFF 地址',
              hintText: 'http://192.168.1.10:8787',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _save(),
          ),
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error,
                style: const TextStyle(
                    fontSize: 11.5, color: AppStatus.danger)),
          ],
          if (_saved.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_saved,
                style: const TextStyle(
                    fontSize: 11.5, color: AppStatus.success)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              GlassChip(
                label: '保存并检测',
                icon: Icons.save_rounded,
                tint: AppColors.pink,
                radius: 11,
                onTap: _save,
              ),
              GlassChip(
                label: '恢复默认',
                icon: Icons.restore_rounded,
                radius: 11,
                onTap: _clear,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, Color sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: 11.5, color: sub))),
        Expanded(
          child: Text(value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}
