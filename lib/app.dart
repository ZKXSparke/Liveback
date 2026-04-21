// Owner: T3 (UI teammate). Reference: Doc 1 §A.8 wire-up + §5.2 routes.
//
// LivebackApp is the MaterialApp root. Two production-ready responsibilities
// are already wired here:
//   1. WidgetsBindingObserver that forwards AppLifecycleState into
//      AppLifecycle.updateState (Doc 1 §A.8 — NotificationService reads it).
//   2. ThemeData.light/dark from LivebackTheme (brand §3).
// Route widgets themselves are Placeholder stubs — T3 replaces each with
// the real page widget.

import 'package:flutter/material.dart';

import 'core/app_lifecycle.dart';
import 'core/theme.dart';

class LivebackApp extends StatefulWidget {
  const LivebackApp({super.key});

  @override
  State<LivebackApp> createState() => _LivebackAppState();
}

class _LivebackAppState extends State<LivebackApp>
    with WidgetsBindingObserver {
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycle.updateState(state);
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liveback',
      debugShowCheckedModeBanner: false,
      theme: LivebackTheme.light(),
      darkTheme: LivebackTheme.dark(),
      initialRoute: '/',
      // Doc 1 §5.2 — 6 named routes. T3 replaces each Placeholder with
      // the real page widget as features are built.
      routes: {
        '/':          (_) => const Placeholder(),  // HomePage
        '/gallery':   (_) => const Placeholder(),  // GalleryPage
        '/tasks':     (_) => const Placeholder(),  // TaskListPage
        '/result':    (_) => const Placeholder(),  // ResultPage
        '/settings':  (_) => const Placeholder(),  // SettingsPage
        '/test-mode': (_) => const Placeholder(),  // TestModePage
      },
    );
  }
}
