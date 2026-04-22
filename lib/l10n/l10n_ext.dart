// BuildContext sugar for AppL10n + ErrorCodes → localized message mapping.
//
// Usage:
//   context.l10n.galleryTitleSelect
//   context.l10n.errorMessageFor(task.errorCode)
//   context.l10n.taskPhaseLabel(TaskPhase.parsing)

import 'package:flutter/widgets.dart';

import '../core/error_codes.dart';
import '../core/task_phase.dart';
import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart' show AppL10n;

extension L10nX on BuildContext {
  /// Shortcut for `AppL10n.of(this)!`. Asserts that MaterialApp's delegates
  /// include AppL10n.delegate (widget tests must provide it via
  /// `localizationsDelegates: AppL10n.localizationsDelegates`).
  AppL10n get l10n {
    final l = AppL10n.of(this);
    assert(l != null,
        'AppL10n missing — widget tree must include AppL10n.delegate in MaterialApp.localizationsDelegates');
    return l!;
  }
}

extension L10nErrorCodeX on AppL10n {
  /// Maps an ErrorCodes constant to its localized user-facing copy.
  /// Unknown codes fall through to `errUnknown`. When [detail] is supplied
  /// for `jpegParse`, uses the detailed variant.
  String errorMessageFor(String? errorCode, {String? detail}) {
    switch (errorCode) {
      case ErrorCodes.jpegParse:
        return (detail != null && detail.isNotEmpty)
            ? errJpegParseDetail(detail)
            : errJpegParse;
      case ErrorCodes.fileTooLarge:
        return errFileTooLarge;
      case ErrorCodes.app1Overflow:
        return errApp1Overflow;
      case ErrorCodes.sefWriteFail:
        return errSefWriteFail;
      case ErrorCodes.writeCorrupt:
        return errWriteCorrupt;
      case ErrorCodes.permission:
        return errPermission;
      case ErrorCodes.alreadySamsung:
        return errAlreadySamsung;
      case ErrorCodes.noMp4:
        return errNoMp4;
      case ErrorCodes.unknown:
      default:
        return errUnknown;
    }
  }

  /// Maps a [TaskPhase] to its localized progress label (TaskList row).
  String taskPhaseLabel(TaskPhase phase) {
    switch (phase) {
      case TaskPhase.parsing:
        return taskPhaseParsing;
      case TaskPhase.injectingSef:
        return taskPhaseInjectingSef;
      case TaskPhase.writing:
        return taskPhaseWriting;
    }
  }
}
