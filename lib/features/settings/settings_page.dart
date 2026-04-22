// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.5 SettingsPage + JSX
// settings.jsx. Simple section-style list with:
//   - masthead (app icon + version)
//   - notification toggle
//   - clear cache action
//   - test mode entry (chevron row)
//   - version row with 7-tap easter egg

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme_mode_controller.dart';
import '../../widgets/dialog/confirm_dialog.dart';
import '../../widgets/dialog/error_dialog.dart';
import '../../widgets/dialog/info_dialog.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/waveform.dart';
import '../home/widgets/app_mark.dart';

const _kNotifEnabledKey = 'liveback.notif_enabled';
const _kTestModeUnlockedKey = 'liveback.test_mode_unlocked';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifEnabled = true;
  int _tapCount = 0;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notifEnabled = p.getBool(_kNotifEnabledKey) ?? true;
      });
    } catch (_) {
      // Ignore — widget defaults are fine.
    }
  }

  Future<void> _setNotif(bool v) async {
    setState(() => _notifEnabled = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kNotifEnabledKey, v);
    } catch (_) {}
  }

  void _tapVersion() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds > 1500) {
      _tapCount = 0;
    }
    _lastTap = now;
    setState(() => _tapCount++);
    if (_tapCount >= 7) {
      _tapCount = 0;
      _unlockTestMode();
    }
  }

  Future<void> _unlockTestMode() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kTestModeUnlockedKey, true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamed('/test-mode');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _masthead(context),
                    _Section(
                      title: '外观',
                      children: [
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable:
                              ThemeModeController.instance.mode,
                          builder: (_, mode, __) => _ThemeModePicker(
                            current: mode,
                            onChange: (m) =>
                                ThemeModeController.instance.setMode(m),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: '通知',
                      children: [
                        _Row(
                          label: '完成后系统通知',
                          sub: '批次处理完成时推送通知',
                          trailing: _Toggle(
                            on: _notifEnabled,
                            onChange: _setNotif,
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: '存储',
                      children: [
                        _Row(
                          label: '清除缓存',
                          sub: '清理画廊缩略图缓存，不会删除输出文件',
                          chevron: true,
                          onTap: () => _showClearCache(context),
                        ),
                      ],
                    ),
                    _Section(
                      title: '工具',
                      children: [
                        _Row(
                          label: '自检',
                          sub: '用内置样本验证格式修复链路',
                          chevron: true,
                          onTap: () => Navigator.of(context)
                              .pushNamed('/test-mode'),
                        ),
                      ],
                    ),
                    _Section(
                      title: '弹窗预览（开发调试）',
                      children: [
                        _Row(
                          label: '信息 · 首次警告',
                          sub: '首次点击处理按钮弹出，可勾选不再提醒',
                          chevron: true,
                          onTap: () => showInfoDialog(
                            context,
                            title: '处理过程提示',
                            body:
                                '处理期间请不要切走应用，否则已排队的任务会丢失。处理完成后会自动通知。',
                            checkboxLabel: '不再提醒',
                          ),
                        ),
                        _Row(
                          label: '确认 · 危险操作',
                          sub: '例如取消全部任务的二次确认',
                          chevron: true,
                          onTap: () => showConfirmDialog(
                            context,
                            title: '取消全部任务？',
                            body: '已处理完成的文件会保留，未开始的会被丢弃。',
                            cancelText: '继续处理',
                            confirmText: '确认取消',
                            destructive: true,
                          ),
                        ),
                        _Row(
                          label: '错误 · 详情',
                          sub: '用户点击失败任务查看原因',
                          chevron: true,
                          onTap: () => showErrorDialog(
                            context,
                            errorCode: 'ERR_SEF_WRITE_FAIL',
                            title: '修复失败',
                            body:
                                '写入 SEF trailer 时文件被其他程序占用，请关闭预览工具后重试，或检查存储权限。',
                            canRetry: true,
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: '关于',
                      children: [
                        _Row(
                          label: '版本',
                          sub: 'Liveback',
                          onTap: _tapVersion,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MonoText(
                                '0.1.0',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.inkDim,
                                ),
                              ),
                              if (_tapCount >= 3 && _tapCount < 7) ...[
                                const SizedBox(width: 6),
                                MonoText(
                                  '· ${7 - _tapCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    _footer(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_ios_new, color: c.ink, size: 20),
          ),
          Expanded(
            child: Text(
              '设置',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.ink,
                letterSpacing: -0.17,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _masthead(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          const AppIconTile(size: 64),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Liveback',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              MonoText(
                '0.1.0',
                style: TextStyle(fontSize: 11, color: c.inkDim),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Opacity(
        opacity: 0.5,
        child: Column(
          children: [
            Waveform(
              width: 220,
              height: 24,
              seed: 17,
              state: WaveformState.clean,
              color: c.inkFaint,
              dim: c.border,
              showGrid: false,
            ),
            const SizedBox(height: 10),
            Text(
              '本应用纯本地处理，不联网',
              style: TextStyle(fontSize: 12, color: c.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: '清除画廊缩略图缓存？',
      body: '这只会清除画廊预览的缩略图，不会影响输出文件。',
      destructive: false,
      confirmText: '清除',
    );
    if (confirmed) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('已清除')),
      );
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title,
              style: TextStyle(fontSize: 13, color: c.inkDim),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              border: Border.all(color: c.border, width: 1),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? sub;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  const _Row({
    required this.label,
    this.sub,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: c.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: TextStyle(fontSize: 12, color: c.inkDim),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (chevron)
              Icon(Icons.chevron_right, color: c.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChange;
  const _Toggle({required this.on, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => onChange(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: on ? c.accent : c.borderStrong,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              top: 2,
              left: on ? 20 : 2,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(0, 1),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChange;

  const _ThemeModePicker({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
      (ThemeMode.light, '浅色', Icons.light_mode_outlined),
      (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '默认跟随系统切换深浅色；可强制固定其中一种',
            style: TextStyle(fontSize: 12, color: c.inkDim, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (mode, label, icon) in options) ...[
                Expanded(
                  child: _ThemeOptionChip(
                    label: label,
                    icon: icon,
                    selected: current == mode,
                    onTap: () => onChange(mode),
                  ),
                ),
                if (mode != options.last.$1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.accent : c.border,
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? c.accent : c.inkDim,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.ink : c.inkDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
