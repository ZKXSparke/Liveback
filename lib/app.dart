// Owner: T3 (UI teammate). Reference: Doc 1 §A.8 wire-up + §5.2 routes.
//
// LivebackApp is the MaterialApp root. Responsibilities:
//   1. WidgetsBindingObserver that forwards AppLifecycleState into
//      AppLifecycle.updateState (Doc 1 §A.8 — NotificationService reads
//      it to decide whether to suppress post-batch notifications).
//   2. Ambient services bootstrap (TaskQueue + NotificationService). Any
//      init failure surfaces in the first frame as a small error banner
//      rather than a crash at main().
//   3. ThemeData.light/dark from LivebackTheme (brand §3).
//   4. Route table per Doc 1 §5.2.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_lifecycle.dart';
import 'core/locale_controller.dart';
import 'core/theme.dart';
import 'core/theme_mode_controller.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/gallery/gallery_page.dart';
import 'features/home/home_page.dart';
import 'features/preview/preview_page.dart';
import 'features/result/result_page.dart';
import 'features/settings/settings_page.dart';
import 'features/splash/splash_page.dart';
import 'features/tasks/task_list_page.dart';
import 'features/test_mode/test_mode_page.dart';
import 'services/notification_service.dart';
import 'services/task_queue.dart';

class LivebackApp extends StatefulWidget {
  const LivebackApp({super.key});

  @override
  State<LivebackApp> createState() => _LivebackAppState();
}

class _LivebackAppState extends State<LivebackApp>
    with WidgetsBindingObserver {
  String? _bootstrapError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed the AppLifecycle with the framework's current reading so that
    // a cold-launch-to-background (rare but possible) doesn't leave the
    // singleton on its default `resumed`.
    AppLifecycle.updateState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // Load persisted theme-mode + locale choices BEFORE first MaterialApp
    // rebuild so the first frame already matches the user's last selection
    // (avoids a flicker from system-default → preferred on cold launch).
    await Future.wait([
      ThemeModeController.instance.load(),
      LocaleController.instance.load(),
    ]);
    try {
      await TaskQueue.instance.init();
    } catch (e, st) {
      debugPrint('LivebackApp: TaskQueue init failed: $e\n$st');
      if (!mounted) return;
      setState(() => _bootstrapError = 'TaskQueue init failed: $e');
    }
    try {
      await NotificationService().init();
    } catch (e) {
      // Notification init failure is non-fatal. Log and carry on.
      debugPrint('LivebackApp: NotificationService init skipped: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(TaskQueue.instance.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycle.updateState(state);
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to BOTH controllers via Listenable.merge — a change in either
    // rebuilds the MaterialApp exactly once per frame boundary.
    final listenable = Listenable.merge([
      ThemeModeController.instance.mode,
      LocaleController.instance.locale,
    ]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (_, __) {
        final mode = ThemeModeController.instance.mode.value;
        final locale = LocaleController.instance.locale.value;
        return MaterialApp(
      title: 'Liveback',
      debugShowCheckedModeBanner: false,
      theme: LivebackTheme.light(),
      darkTheme: LivebackTheme.dark(),
      themeMode: mode,
      locale: locale, // null ⇒ defer to localeResolutionCallback
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // When the user's explicit choice is null (system-follow), pick zh
      // if the device locale is Chinese-anything; otherwise FALL BACK TO
      // ENGLISH. Do NOT let Flutter's default "first supported locale"
      // resolution fire (supportedLocales[0] is en here, which happens to
      // match, but keep this explicit so it survives list reordering).
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale?.languageCode == 'zh') return const Locale('zh');
        return const Locale('en');
      },
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
      builder: (ctx, child) {
        // Status / nav bar chrome follows the app's scaffold background so
        // the top edge reads as one continuous surface. Icon brightness is
        // inverted against the bg; navigation bar uses the same bg with
        // matching divider so it disappears on gesture-nav devices.
        final theme = Theme.of(ctx);
        final bg = theme.scaffoldBackgroundColor;
        final iconBrightness = theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
        final overlay = SystemUiOverlayStyle(
          statusBarColor: bg,
          statusBarIconBrightness: iconBrightness,
          statusBarBrightness: theme.brightness,
          systemNavigationBarColor: bg,
          systemNavigationBarIconBrightness: iconBrightness,
          systemNavigationBarDividerColor: bg,
        );
        final Widget body = _bootstrapError != null
            ? _BootstrapErrorBanner(
                message: _bootstrapError!,
                child: child ?? const SizedBox.shrink(),
              )
            : (child ?? const SizedBox.shrink());
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: body,
        );
      },
    );
      },
    );
  }

  Route<Object?>? _onGenerateRoute(RouteSettings settings) {
    final widget = switch (settings.name) {
      '/' => const SplashPage(),
      '/home' => const HomePage(),
      '/gallery' => const GalleryPage(),
      '/tasks' => const TaskListPage(),
      '/settings' => const SettingsPage(),
      '/test-mode' => const TestModePage(),
      '/result' => ResultPage(taskId: settings.arguments as String? ?? ''),
      '/preview' =>
        PreviewPage(args: settings.arguments as PreviewPageArgs),
      _ => null,
    };
    if (widget == null) return null;
    return MaterialPageRoute<Object?>(
      settings: settings,
      builder: (_) => widget,
    );
  }
}

class _BootstrapErrorBanner extends StatelessWidget {
  final String message;
  final Widget child;
  const _BootstrapErrorBanner({
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.paddingOf(context).top,
          child: Material(
            color: const Color(0xFFE11D74),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
