// Owner: T3 (UI teammate). Reference: Doc 1 §1 directory layout.
//
// Minimal bootstrap. The real bring-up (TaskQueue.init(),
// NotificationService.init(), SharedPreferences warm-up) belongs inside
// LivebackApp.initState so we can surface init failures in the first
// frame. Keeping main.dart bare avoids duplicating that logic here.

import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO(T3): bootstrap TaskQueue.instance.init() + NotificationService.init()
  //           inside LivebackApp.initState; surface errors in the first frame.
  runApp(const LivebackApp());
}
