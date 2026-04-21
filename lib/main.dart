// Owner: T3 (UI teammate). Reference: Doc 1 §1 directory layout.
//
// Minimal bootstrap. Heavy init (TaskQueue.instance.init() +
// NotificationService().init()) runs inside LivebackApp.initState so any
// failure can surface in the first frame without crashing the Dart VM at
// entry.

import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivebackApp());
}
