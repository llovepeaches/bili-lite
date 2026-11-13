import 'package:flutter/material.dart';

import '../../core/card_style.dart';
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
    final sub = context.subTextColor;
    return SettingsCard(
      title: '界面与导航',
      children: <Widget>[
        AnimatedBuilder(
          animation: prefs,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('视频卡片样式',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${prefs.cardStyle.label}：${prefs.cardStyle.hint}',
                style: TextStyle(fontSize: 11.5, color: sub),
              ),
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
              const SizedBox(height: 4),
              Text(
                '可调整入口顺序或隐藏用不到的部分，至少保留一个。',
                style: TextStyle(fontSize: 11.5, color: sub),
              ),
              const SizedBox(height: 10),
              const NavConfigEditor(),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('滚动时收起底部导航',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: prefs.hideDockOnScroll,
                    activeColor: AppColors.pink,
                    onChanged: (v) => prefs.setHideDockOnScroll(v),
                  ),
                ],
              ),
              Text(
                '向下滚动列表时自动收起底部导航，把整屏留给内容；'
                '向上滚动或切换页面时自动恢复。宽屏使用侧边栏，不受影响。',
                style: TextStyle(fontSize: 11, color: sub, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「液态玻璃」区块：材质开关、强度、透镜 / 着色、动态光晕。
class GlassSection extends StatelessWidget {
  const GlassSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sub = context.subTextColor;
    return SettingsCard(
      title: '液态玻璃',
      children: <Widget>[
        AnimatedBuilder(
          animation: appState,
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('玻璃材质',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: appState.glassEnabled,
                    activeColor: AppColors.pink,
                    onChanged: (v) => appState.setGlassEnabled(v),
                  ),
                ],
              ),
              Text(
                  '当前：${appState.glassEnabled ? appState.glassStrengthLabel : '已关闭'}',
                  style: TextStyle(fontSize: 11.5, color: sub)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _strengthChip('轻微', 0.45),
                  _strengthChip('标准', 0.75),
                  _strengthChip('浓郁', 1.0),
                ],
              ),
              const SizedBox(height: 14),
              Text('材质（对应 iOS 26.1 的 Clear / Tinted）',
                  style: TextStyle(fontSize: 12, color: sub)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _materialChip('通透 Clear', false),
                  _materialChip('着色 Tinted', true),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('动态光晕',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: appState.glassEnabled && appState.glassMotion,
                    activeColor: AppColors.pink,
                    onChanged: appState.glassEnabled
                        ? (v) => appState.setGlassMotion(v)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'iOS 26 式透镜材质：内部近乎全透，靠沿边缘的折射亮环、色散与镜面亮斑定义形状；'
                '通透档最接近原生观感，着色档抬高不透明度以提升文字可读性。'
                '低配设备或浏览器可关闭材质与光晕以提升流畅度，设置保存在本机。',
                style: TextStyle(fontSize: 11, color: sub, height: 1.55),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _strengthChip(String label, double value) {
    final selected = appState.glassEnabled && appState.glassStrength == value;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: appState.glassEnabled
          ? () => appState.setGlassStrength(value)
          : null,
    );
  }

  Widget _materialChip(String label, bool tinted) {
    final selected = appState.glassEnabled && appState.glassTinted == tinted;
    return GlassChip(
      label: label,
      selected: selected,
      tint: AppColors.pink,
      radius: 11,
      onTap: appState.glassEnabled
          ? () => appState.setGlassTinted(tinted)
          : null,
    );
  }
}

/// 设置页统一的玻璃卡片外壳。
class SettingsCard extends StatelessWidget {
  const SettingsCard({Key? key, required this.title, required this.children})
      : super(key: key);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionTitle(title: title),
          const SizedBox(height: 4),
          ...children,
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
