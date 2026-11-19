import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/update_service.dart';
import '../../widgets/glass.dart';
import 'settings_sections.dart';

/// 设置页「版本更新」卡片：显示当前版本、检查结果与前往下载的入口。
///
/// 版本串直接读 [kAppVersionLabel] / [kReleaseTag]，不再像旧版那样写死
/// `'1.4.0'`；CI 会强制校验这两个常量与 pubspec、发布 tag 一致。
class UpdateSection extends StatefulWidget {
  const UpdateSection({Key? key}) : super(key: key);

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  final UpdateService _service = UpdateService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // 个别平台没有外部浏览器时静默失败，发布页地址在卡片里可见
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    final info = _service.last;
    final checking = _service.checking;

    return SettingsCard(
      title: '版本更新',
      children: <Widget>[
        SettingsRow('当前版本', kAppVersionLabel),
        SettingsRow('发布标记', kReleaseTag),
        if (info != null)
          SettingsRow(
            '检查结果',
            _statusText(info),
            valueColor: info.hasUpdate ? AppStatus.success : null,
          ),
        if (info?.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(info!.message!,
                style: TextStyle(fontSize: 11.5, height: 1.5, color: sub)),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            GlassChip(
              label: checking ? '检查中…' : '检查更新',
              icon: Icons.system_update_alt_rounded,
              tint: AppColors.pink,
              radius: 11,
              onTap: checking ? null : () => _service.check(),
            ),
            if (info?.hasUpdate == true)
              GlassChip(
                label: '前往下载',
                icon: Icons.open_in_new_rounded,
                radius: 11,
                onTap: () => _open(info!.releaseUrl ?? kReleasesPage),
              ),
            GlassChip(
              label: '发布页',
              icon: Icons.public_rounded,
              radius: 11,
              onTap: () => _open(kReleasesPage),
            ),
          ],
        ),
      ],
    );
  }

  String _statusText(UpdateInfo info) {
    switch (info.status) {
      case UpdateCheckStatus.checking:
        return '检查中';
      case UpdateCheckStatus.upToDate:
        return '已是最新';
      case UpdateCheckStatus.available:
        return '有可用更新';
      case UpdateCheckStatus.failed:
        return '检查未完成';
      default:
        return '尚未检查';
    }
  }
}
