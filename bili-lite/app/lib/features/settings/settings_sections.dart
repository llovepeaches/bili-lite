import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/card_style.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../state/globals.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';
import 'nav_config_editor.dart';

/// 「外观」区块：主题模式。
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return SettingsCard(
      title: '外观',
      storageKey: 'bili_lite_settings_appearance',
      children: <Widget>[
        AnimatedBuilder(
          animation: appState,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('当前：${appState.themeLabel}',
                  style: TextStyle(fontSize: 12, color: sub)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _themeChip('跟随系统', ThemeMode.system),
                  _themeChip('浅色', ThemeMode.light),
                  _themeChip('深色', ThemeMode.dark),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _themeChip(String label, ThemeMode mode) {
    final selected = appState.themeMode == mode;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: () => appState.setThemeMode(mode),
    );
  }
}

/// 「界面与导航」区块：卡片样式、导航入口顺序、滚动收起底部导航。
class InterfaceSection extends StatelessWidget {
  const InterfaceSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: '界面与导航',
      storageKey: 'bili_lite_settings_interface',
      children: <Widget>[
        AnimatedBuilder(
          animation: prefs,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('视频卡片样式',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CardStyle.values
                    .map((style) => GlassChip(
                          label: style.label,
                          selected: prefs.cardStyle == style,
                          tint: AppColors.pink,
                          radius: 11,
                          onTap: () => prefs.setCardStyle(style),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Text('导航入口',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const NavConfigEditor(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 设置页统一的卡片外壳：标题可点击折叠，折叠偏好可持久化。
///
/// 折叠用于收起次要设置项：
///   * 需要随时能点的操作项放进 [alwaysVisible]，折叠时依然常驻；
///   * [AnimatedCrossFade] 提供平滑的高度过渡，箭头同步旋转；
///   * 传了 [storageKey] 就记住用户上次展开/收起的选择，下次进来不反弹。
///
/// 折叠只影响展示，不销毁任何业务状态：所有设置项的读写仍走原来的
/// State / ChangeNotifier，展开后重新构建即可。
class SettingsCard extends StatefulWidget {
  const SettingsCard({
    Key? key,
    required this.title,
    required this.children,
    this.initiallyCollapsed = false,
    this.collapsedHint = '',
    this.storageKey,
    this.alwaysVisible = const <Widget>[],
    this.collapsible = true,
  }) : super(key: key);

  final String title;
  final List<Widget> children;

  /// 首次进入（且本机没有保存过偏好）时是否收起。
  final bool initiallyCollapsed;

  /// 收起时标题下的一行摘要；为空则折叠后标题行就是整张卡片。
  final String collapsedHint;

  /// 传入后把展开状态存到本机；不传则只在本次页面生命周期内有效。
  final String? storageKey;

  /// 折叠时仍然显示的内容：按钮、开关等需要随时可点的操作项。
  final List<Widget> alwaysVisible;

  /// 设为 false 退化为普通常驻卡片（不显示箭头、不响应点击）。
  final bool collapsible;

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    final key = widget.storageKey;
    final saved = key == null ? null : LocalStore.instance.getBool(key);
    _expanded =
        widget.collapsible ? (saved ?? !widget.initiallyCollapsed) : true;
  }

  void _toggle() {
    if (!widget.collapsible) return;
    final next = !_expanded;
    setState(() => _expanded = next);
    final key = widget.storageKey;
    if (key != null) unawaited(LocalStore.instance.setBool(key, next));
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.collapsible ? _toggle : null,
            child: Row(
              children: <Widget>[
                Expanded(child: SectionTitle(title: widget.title)),
                if (widget.collapsible) ...<Widget>[
                  const SizedBox(width: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: _expanded ? 1.0 : 0.0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    builder: (_, double t, __) => Transform.rotate(
                      angle: t * math.pi,
                      child:
                          Icon(Icons.expand_more_rounded, size: 20, color: sub),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.alwaysVisible.isNotEmpty) ...widget.alwaysVisible,
          if (widget.collapsible)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 260),
              sizeCurve: Curves.easeOutCubic,
              firstCurve: Curves.easeOutCubic,
              secondCurve: Curves.easeOutCubic,
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: SizedBox(
                width: double.infinity,
                child: widget.collapsedHint.isEmpty
                    ? const SizedBox(height: 0)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                        child: Text(
                          widget.collapsedHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: sub, height: 1.45),
                        ),
                      ),
              ),
              secondChild: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 4),
                    ...widget.children,
                  ],
                ),
              ),
            )
          else ...<Widget>[
            const SizedBox(height: 4),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}

/// 「键值」行：左标签、右值。
class SettingsRow extends StatelessWidget {
  const SettingsRow(this.label, this.value, {Key? key, this.valueColor})
      : super(key: key);

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(label,
                style: TextStyle(
                    fontSize: AppFontSize.body, color: context.subTextColor)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: AppFontSize.body, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
