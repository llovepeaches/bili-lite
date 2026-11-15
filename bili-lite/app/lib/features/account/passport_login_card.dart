import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/passport_api.dart';
import '../../state/globals.dart';
import '../../state/qr_session.dart';
import '../../widgets/glass.dart';
import '../../widgets/segmented_switch.dart';
import '../../widgets/state_views.dart';
import 'account_identity.dart';
import 'qr_login_sheet.dart';

/// 「其他登录方式」卡片：账号密码 / 短信验证码 / Cookie。
///
/// 三条通道的产物都是同一份 B 站 Web 登录 Cookie，最终统一交给
/// `QrSession.applyCookie()` 落地，因此账号面板里不会出现第四套身份状态。
///
/// **诚实边界**（必须让用户看见）：B 站对 Web 密码 / 短信登录强制极验滑块，
/// `validate` / `seccode` 只能由浏览器里的极验 JS 生成，纯 Dart 客户端
/// 无法自行产出。所以这里保留真实接口链路（RSA 加密、发短信、提交登录），
/// 但遇到 -105 / -412 / 2400 / 2406 时不伪造凭证，而是明确引导用户改用
/// 扫码登录或粘贴浏览器里已登录的 Cookie。Cookie 登录是三条里唯一
/// 无条件可用的一条：先经 nav 校验有效，才写入本机。
class PassportLoginCard extends StatefulWidget {
  const PassportLoginCard({Key? key}) : super(key: key);

  @override
  State<PassportLoginCard> createState() => _PassportLoginCardState();
}

class _PassportLoginCardState extends State<PassportLoginCard> {
  static const List<String> _tabs = <String>['账号密码', '短信验证码', 'Cookie'];

  int _tab = 0;
  bool _busy = false;
  bool _needsCaptcha = false;
  String _error = '';
  String _info = '';

  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _tel = TextEditingController();
  final TextEditingController _smsCode = TextEditingController();
  final TextEditingController _cookie = TextEditingController();

  /// 短信发送接口返回的 captcha_key，登录时原样带回。
  String _captchaKey = '';

  /// 人机验证 challenge（不含 validate / seccode，本应用不伪造）。
  CaptchaChallenge? _challenge;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _tel.dispose();
    _smsCode.dispose();
    _cookie.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (_busy) return;
    setState(() {
      _tab = index;
      _error = '';
      _info = '';
      _needsCaptcha = false;
    });
  }

  /// 统一的「跑一次网络操作」外壳：忙态、错误映射、成功后关闭弹层。
  ///
  /// [closeOnSuccess] 仅用于真正的登录动作；「获取验证码」成功后要留在
  /// 原表单继续填验证码，所以用 [successMessage] 给出可见反馈。
  Future<void> _run(
    Future<void> Function() action, {
    bool closeOnSuccess = false,
    String successMessage = '操作完成',
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
      _info = '';
      _needsCaptcha = false;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = closeOnSuccess ? '登录成功' : successMessage;
      });
      if (closeOnSuccess) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).maybePop();
      }
    } on PassportException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _needsCaptcha = e.needsCaptcha;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '登录失败：$e';
      });
    }
  }

  // ------------------------------------------------------------------
  // 三条通道：真实接口链路，绝不伪造登录态
  // ------------------------------------------------------------------

  Future<void> _submitPassword() => _run(() async {
        final username = _username.text.trim();
        final password = _password.text;
        if (username.isEmpty || password.isEmpty) {
          throw const PassportException('请填写账号与密码');
        }
        final api = PassportApi.instance;
        final key = await api.fetchKey();
        final encrypted =
            PassportApi.encryptPassword(key.hash, key.pem, password);
        final c = _challenge;
        final cookie = await api.passwordLogin(
          username: username,
          encryptedPassword: encrypted,
          token: c?.token ?? '',
          challenge: c?.challenge ?? '',
        );
        await qrSession.applyCookie(cookie, LoginMethod.password);
      }, closeOnSuccess: true);

  Future<void> _sendSms() => _run(() async {
        final tel = _tel.text.trim();
        if (!_validTel(tel)) {
          throw const PassportException('请填写有效的 11 位中国大陆手机号');
        }
        final api = PassportApi.instance;
        final c = await api.fetchCaptcha();
        _challenge = c;
        final result = await api.sendSmsCode(
          tel: tel,
          token: c.token,
          challenge: c.challenge,
        );
        _captchaKey = result.captchaKey;
      }, successMessage: '验证码已发送，请查收短信后填写');

  Future<void> _submitSms() => _run(() async {
        final tel = _tel.text.trim();
        final code = _smsCode.text.trim();
        if (!_validTel(tel)) {
          throw const PassportException('请填写有效的 11 位中国大陆手机号');
        }
        if (code.isEmpty) {
          throw const PassportException('请填写短信验证码');
        }
        if (_captchaKey.isEmpty) {
          throw const PassportException('请先点「获取验证码」');
        }
        final cookie = await PassportApi.instance.smsLogin(
          tel: tel,
          code: code,
          captchaKey: _captchaKey,
        );
        await qrSession.applyCookie(cookie, LoginMethod.sms);
      }, closeOnSuccess: true);

  Future<void> _submitCookie() => _run(() async {
        // normalizeCookie 会强制要求 SESSDATA + bili_jct，缺一个都不写入本机。
        final cookie = PassportApi.normalizeCookie(_cookie.text);
        await qrSession.applyCookie(cookie, LoginMethod.cookie);
      }, closeOnSuccess: true);

  static bool _validTel(String raw) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(raw);

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AccountIdentity.changes,
      builder: (context, _) {
        // 已登录时不再展示表单，避免「登录后还能再登录一次」的歧义。
        if (AccountIdentity.signedIn) return const SizedBox.shrink();
        return _card(context);
      },
    );
  }

  Widget _card(BuildContext context) {
    final sub = context.subTextColor;
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle(title: '其他登录方式'),
          Text(
            '扫码登录最省事。B 站对 Web 密码 / 短信登录强制要求滑块验证，'
            '滑块凭证只能由浏览器里的极验组件生成，本应用不会伪造：'
            '遇到「需要人机验证」请改用扫码，或在浏览器登录后复制 Cookie。',
            style: TextStyle(fontSize: 11.5, color: sub, height: 1.55),
          ),
          const SizedBox(height: 12),
          GlassSegmented(labels: _tabs, index: _tab, onChanged: _switchTab),
          const SizedBox(height: 14),
          if (_tab == 0)
            _passwordForm(sub)
          else if (_tab == 1)
            _smsForm(sub)
          else
            _cookieForm(sub),
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _notice(_error, true, sub),
          ],
          if (_info.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _notice(_info, false, sub),
          ],
        ],
      ),
    );
  }

  Widget _passwordForm(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _field(
          controller: _username,
          label: '账号（手机号 / 邮箱 / 用户名）',
          icon: Icons.person_outline_rounded,
          sub: sub,
        ),
        _field(
          controller: _password,
          label: '密码',
          icon: Icons.lock_outline_rounded,
          sub: sub,
          obscure: true,
        ),
        Text(
          '密码在本机用 B 站下发的 RSA 公钥加密后提交，不保存、不上传第三方。',
          style: TextStyle(fontSize: 11, color: sub, height: 1.5),
        ),
        const SizedBox(height: 10),
        _actions(<Widget>[
          _button('账号密码登录', Icons.login_rounded, _submitPassword,
              primary: true),
        ]),
      ],
    );
  }

  Widget _smsForm(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _field(
          controller: _tel,
          label: '手机号',
          icon: Icons.phone_android_rounded,
          sub: sub,
          keyboardType: TextInputType.phone,
          hint: '11 位中国大陆手机号',
        ),
        _field(
          controller: _smsCode,
          label: '短信验证码',
          icon: Icons.sms_rounded,
          sub: sub,
          keyboardType: TextInputType.number,
          hint: '短信中的数字验证码',
        ),
        if (_captchaKey.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('已取得验证码凭证，填入短信验证码后即可登录',
                style: TextStyle(fontSize: 11, color: AppStatus.success)),
          ),
        _actions(<Widget>[
          _button('获取验证码', Icons.send_rounded, _sendSms),
          _button('短信登录', Icons.login_rounded, _submitSms, primary: true),
        ]),
      ],
    );
  }

  Widget _cookieForm(Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '在浏览器登录 bilibili.com 后，从 DevTools → Application → Cookies '
          '复制整串 Cookie，或直接复制 Network 请求头里的 Cookie。'
          '必须同时包含 SESSDATA 与 bili_jct，通过 nav 校验后才会写入本机。',
          style: TextStyle(fontSize: 11.5, color: sub, height: 1.55),
        ),
        const SizedBox(height: 10),
        _field(
          controller: _cookie,
          label: '登录 Cookie',
          icon: Icons.vpn_key_rounded,
          sub: sub,
          maxLines: 4,
          hint: 'SESSDATA=...; bili_jct=...; DedeUserID=...',
        ),
        _actions(<Widget>[
          _button('校验并登录', Icons.verified_user_outlined, _submitCookie,
              primary: true),
        ]),
      ],
    );
  }

  /// 轻量输入框：登录表单属于内容层，刻意不叠 BackdropFilter 玻璃，
  /// 避免多层滤镜影响焦点与文本选择（全局玻璃语言由外层卡片承担）。
  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color sub,
    String hint = '',
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final dark = context.isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: (dark ? Colors.white : Colors.black).withOpacity(0.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sub.withOpacity(0.22)),
        ),
        child: TextField(
          controller: controller,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint.isEmpty ? null : hint,
            labelStyle: TextStyle(fontSize: 12, color: sub),
            hintStyle: TextStyle(fontSize: 11, color: sub.withOpacity(0.7)),
            prefixIcon: Icon(icon, size: 17, color: sub),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 38, maxHeight: 38),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
      ),
    );
  }

  Widget _actions(List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      );

  Widget _button(String label, IconData icon, VoidCallback? onTap,
          {bool primary = false}) =>
      GlassChip(
        label: _busy && primary ? '处理中…' : label,
        icon: icon,
        tint: primary ? AppColors.pink : null,
        radius: 11,
        onTap: _busy ? null : onTap,
      );

  Widget _notice(String text, bool error, Color sub) {
    final color = error ? AppStatus.warning : AppStatus.success;
    return GlassPanel(
      radius: 14,
      padding: const EdgeInsets.all(11),
      tint: color.withOpacity(0.10),
      showSheen: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 11.5, color: sub, height: 1.5)),
              ),
            ],
          ),
          if (error && _needsCaptcha) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                GlassChip(
                  label: '改用扫码登录',
                  icon: Icons.qr_code_scanner_rounded,
                  tint: AppColors.pink,
                  radius: 11,
                  onTap: () => showQrLoginSheet(context),
                ),
                GlassChip(
                  label: '粘贴 Cookie',
                  icon: Icons.content_paste_rounded,
                  radius: 11,
                  onTap: () => _switchTab(2),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
