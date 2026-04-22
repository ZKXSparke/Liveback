// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.5 SettingsPage + JSX
// settings.jsx. Simple section-style list with:
//   - masthead (app icon + version)
//   - notification toggle
//   - clear cache action
//   - test mode entry (chevron row)
//   - version row with 7-tap easter egg

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/locale_controller.dart';
import '../../core/theme_mode_controller.dart';
import '../../l10n/l10n_ext.dart';
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
    final l = context.l10n;
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
                    // Language first — it affects every other label on this
                    // page.
                    _Section(
                      title: l.settingsLanguageSection,
                      children: [
                        ValueListenableBuilder<Locale?>(
                          valueListenable:
                              LocaleController.instance.locale,
                          builder: (_, locale, __) => _LanguagePicker(
                            current: locale,
                            onChange: (loc) =>
                                LocaleController.instance.setLocale(loc),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: l.settingsAppearanceSection,
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
                      title: l.settingsNotificationSection,
                      children: [
                        _Row(
                          label: l.settingsNotifRowLabel,
                          sub: l.settingsNotifRowSub,
                          trailing: _Toggle(
                            on: _notifEnabled,
                            onChange: _setNotif,
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: l.settingsStorageSection,
                      children: [
                        _Row(
                          label: l.settingsClearCacheLabel,
                          sub: l.settingsClearCacheSub,
                          chevron: true,
                          onTap: () => _showClearCache(context),
                        ),
                      ],
                    ),
                    _Section(
                      title: l.settingsToolsSection,
                      children: [
                        _Row(
                          label: l.settingsTestModeLabel,
                          sub: l.settingsTestModeSub,
                          chevron: true,
                          onTap: () => Navigator.of(context)
                              .pushNamed('/test-mode'),
                        ),
                      ],
                    ),
                    _Section(
                      title: l.settingsDialogPreviewSection,
                      children: [
                        _Row(
                          label: l.settingsDlgInfoLabel,
                          sub: l.settingsDlgInfoSub,
                          chevron: true,
                          onTap: () => showInfoDialog(
                            context,
                            title: l.settingsDlgInfoTitle,
                            body: l.settingsDlgInfoBody,
                            checkboxLabel: l.settingsDlgInfoCheckbox,
                          ),
                        ),
                        _Row(
                          label: l.settingsDlgConfirmLabel,
                          sub: l.settingsDlgConfirmSub,
                          chevron: true,
                          onTap: () => showConfirmDialog(
                            context,
                            title: l.tasksCancelAllTitle,
                            body: l.tasksCancelAllBody,
                            cancelText: l.tasksCancelAllKeep,
                            confirmText: l.tasksCancelAllConfirm,
                            destructive: true,
                          ),
                        ),
                        _Row(
                          label: l.settingsDlgErrorLabel,
                          sub: l.settingsDlgErrorSub,
                          chevron: true,
                          onTap: () => showErrorDialog(
                            context,
                            errorCode: 'ERR_SEF_WRITE_FAIL',
                            title: l.errorDialogDefaultFailureTitle,
                            body: l.settingsDlgErrorBody,
                            canRetry: true,
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: l.settingsAboutSection,
                      children: [
                        _Row(
                          label: l.settingsVersionLabel,
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
              context.l10n.settingsTitle,
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
              context.l10n.settingsFooter,
              style: TextStyle(fontSize: 12, color: c.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearCache(BuildContext context) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final clearedMsg = l.settingsClearCacheCleared;
    final confirmed = await showConfirmDialog(
      context,
      title: l.settingsClearCacheTitle,
      body: l.settingsClearCacheBody,
      destructive: false,
      confirmText: l.settingsClearCacheConfirm,
    );
    if (confirmed) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(clearedMsg)),
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
    final l = context.l10n;
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, l.themeSystem, Icons.brightness_auto_outlined),
      (ThemeMode.light, l.themeLight, Icons.light_mode_outlined),
      (ThemeMode.dark, l.themeDark, Icons.dark_mode_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsThemeHeader,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.settingsThemeDescription,
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

/// Three-option locale picker mirroring [_ThemeModePicker]'s layout. The
/// three options are: null (system) / Locale('en') / Locale('zh'). We
/// reuse [_ThemeOptionChip] for visual parity.
class _LanguagePicker extends StatelessWidget {
  final Locale? current;
  final ValueChanged<Locale?> onChange;

  const _LanguagePicker({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final options = <(Locale?, String, IconData)>[
      (null, l.languagePickerSystem, Icons.translate_outlined),
      (const Locale('en'), l.languagePickerEn, Icons.language_outlined),
      (const Locale('zh'), l.languagePickerZh, Icons.language_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsLanguageHeader,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.settingsLanguageDescription,
            style: TextStyle(fontSize: 12, color: c.inkDim, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                Expanded(
                  child: _ThemeOptionChip(
                    label: options[i].$2,
                    icon: options[i].$3,
                    selected: _localeEquals(current, options[i].$1),
                    onTap: () => onChange(options[i].$1),
                  ),
                ),
                if (i != options.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static bool _localeEquals(Locale? a, Locale? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.languageCode == b.languageCode;
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
