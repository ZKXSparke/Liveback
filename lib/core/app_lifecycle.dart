// Owner: shared (Phase 1 SSoT). Reference: Doc 1 §A.8.
// DO NOT edit without an architecture amendment.
//
// The WidgetsBindingObserver that updates this state lives in `app.dart`
// (LivebackApp's State) — it owns the only write to AppLifecycle._state via
// the library-private setter below. NotificationService.postBatchComplete
// reads isForeground here to decide whether to suppress a batch-complete
// notification (v1.1 §3.1 F6 + review B8).

import 'package:flutter/widgets.dart';

/// Process-wide foreground/background state, updated by a
/// [WidgetsBindingObserver] registered in `app.dart`'s [State.initState].
///
/// `static`-only surface by design: this is a pure state holder with no
/// lifecycle of its own. Callers do NOT subscribe to changes — they read
/// [isForeground] synchronously at decision points (e.g. when the Worker
/// finishes a batch and the notification service considers whether to post).
class AppLifecycle {
  AppLifecycle._();

  static AppLifecycleState _state = AppLifecycleState.resumed;

  static AppLifecycleState get state => _state;

  /// True iff the app is currently in the foreground. Read by
  /// NotificationService to skip no-op notifications (Doc 1 §A.8 rationale).
  static bool get isForeground => _state == AppLifecycleState.resumed;

  /// Library-private setter invoked by the [WidgetsBindingObserver] in
  /// `app.dart`. Not intended for any other caller.
  ///
  /// The leading underscore makes this private to the `liveback` package
  /// root; cross-library access requires the `app.dart` wire-up.
  // ignore: library_private_types_in_public_api
  static set debugStateForTest(AppLifecycleState value) => _state = value;

  /// Called by the app.dart observer. Separate from [debugStateForTest] so
  /// tests and the observer can both write without `@visibleForTesting`
  /// leaking into production call sites.
  static void updateState(AppLifecycleState value) {
    _state = value;
  }
}
