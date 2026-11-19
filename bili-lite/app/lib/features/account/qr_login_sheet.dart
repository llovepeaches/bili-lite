import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../state/qr_session.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';

/// 打开扫码登录弹层。关闭时自动停止轮询，不会在后台一直打 B 站接口。
Future<void> showQrLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _QrLoginSheet(),
  );
}

class _QrLoginSheet extends StatefulWidget {
  const _QrLoginSheet();

  @override
  State<_QrLoginSheet> createState() => _QrLoginSheetState();
}

class _QrLoginSheetState extends State<_QrLoginSheet> {
  @override
  void initState() {
    super.initState();
    // 首帧后再发起，避免在 build 期间 notifyListeners。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qrSession.start();
    });
    qrSession.addListener(_onSignedIn);
  }

  void _onSignedIn() {
    if (qrSession.signedIn && mounted) {
      // 登录成功后稍等一下再关，让用户看到「登录成功」。
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    qrSession.removeListener(_onSignedIn);
    qrSession.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF161822) : const Color(0xFFF6F7FB),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: qrSession,
              builder: (_, __) => _body(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = qrSession;
    switch (s.status) {
      case QrStatus.generating:
        return _loading('正在向 B 站申请二维码…');
      case QrStatus.signedIn:
        return _success();
      case QrStatus.error:
        return _error(s.message);
      case QrStatus.expired:
        return _expired(s.message);
      case QrStatus.waiting:
      case QrStatus.scanned:
      case QrStatus.signedOut:
        return _qrCode(s);
    }
  }

  Widget _qrCode(QrSession s) {
    final challenge = s.challenge;
    final scanned = s.status == QrStatus.scanned;
    return Column(
      children: <Widget>[
        const SectionTitle(title: 'B 站扫码登录'),
        const SizedBox(height: 6),
        Text(
          '打开手机上的哔哩哔哩 App →「我的」→ 扫一扫，扫描下方二维码并在手机上确认。',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 12, height: 1.6, color: context.subTextColor),
        ),
        const SizedBox(height: 18),
        if (challenge == null)
          _loading('正在准备二维码…')
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: QrImage(
              data: challenge.url,
              version: QrVersions.auto,
              size: 210,
              padding: const EdgeInsets.all(8),
              backgroundColor: Colors.white,
              // 内容过长时给一个明确的错误提示，而不是空白方块
              errorStateBuilder: (context, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('二维码生成失败：$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _statusLine(s.message, scanned ? AppColors.pink : AppStatus.neutral),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            GlassChip(
              label: '刷新二维码',
              icon: Icons.refresh_rounded,
              tint: AppColors.pink,
              radius: 11,
              onTap: s.busy ? null : () => qrSession.start(),
            ),
            GlassChip(
              label: '取消',
              icon: Icons.close_rounded,
              radius: 11,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _loading(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        children: <Widget>[
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _success() {
    final u = qrSession.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded,
              size: 54, color: AppStatus.success),
          const SizedBox(height: 16),
          Text('登录成功${u == null ? '' : '，${u.name}'}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('凭证已保存在本机，关闭后即可使用。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _error(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              size: 44, color: AppStatus.danger),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.6)),
          const SizedBox(height: 18),
          GlassChip(
            label: '重新获取二维码',
            icon: Icons.refresh_rounded,
            tint: AppColors.pink,
            radius: 11,
            onTap: () => qrSession.start(),
          ),
        ],
      ),
    );
  }

  Widget _expired(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          const Icon(Icons.schedule_rounded, size: 44, color: AppColors.pink),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.6)),
          const SizedBox(height: 18),
          GlassChip(
            label: '刷新二维码',
            icon: Icons.refresh_rounded,
            tint: AppColors.pink,
            radius: 11,
            onTap: () => qrSession.start(),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(String text, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 15, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.5)),
        ),
      ],
    );
  }
}
