// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Liveback';

  @override
  String bootstrapTaskQueueFailed(String error) {
    return 'TaskQueue init failed: $error';
  }

  @override
  String get homeMastheadLine1 => 'Make your\n';

  @override
  String get homeMastheadEmphasis => 'Motion Photos';

  @override
  String get homeMastheadTail => ' move again';

  @override
  String get homePrimaryCta => 'Select Motion Photos';

  @override
  String get homePrimaryCtaSubtitle => 'Batch up to 100 at once';

  @override
  String get statusChipReady => 'READY';

  @override
  String get statusChipSyncing => 'SYNCING';

  @override
  String get statusChipError => 'ERROR';

  @override
  String get fixedCounterLabel => 'FIXED';

  @override
  String get localOfflineLabel => 'LOCAL · OFFLINE';

  @override
  String get galleryTitleSelect => 'Select Motion Photos';

  @override
  String get galleryTitleAllAlbums => 'All albums';

  @override
  String galleryDoneButton(String selection) {
    return 'Done · $selection';
  }

  @override
  String gallerySelectionRatio(int selected, int max) {
    return '$selected/$max';
  }

  @override
  String gallerySelectionHidden(int selected, int max, int hidden) {
    return '$selected/$max · +$hidden selected but hidden';
  }

  @override
  String get filterAll => 'All';

  @override
  String get filterMotionOnly => 'Motion Photos only';

  @override
  String get filterNeedsFix => 'Needs fix';

  @override
  String get albumPickerTitle => 'Select album';

  @override
  String get albumPickerAllAlbums => 'All albums';

  @override
  String get albumPickerEmpty => 'No albums in gallery';

  @override
  String albumPickerCount(int count) {
    return '$count photos';
  }

  @override
  String get galleryEmptyTitle => 'No photos in gallery';

  @override
  String get galleryEmptyBody =>
      'Shoot a Motion Photo or import from an album first';

  @override
  String get galleryFilteredEmptyAll => 'No photos in this album';

  @override
  String get galleryFilteredEmptyMotion =>
      'No Motion Photos match the current filter';

  @override
  String get galleryFilteredEmptyNeedsFix => 'No Motion Photos need fixing';

  @override
  String get galleryNoMore => 'No more photos';

  @override
  String get galleryNoMoreFiltered => 'No more matching photos';

  @override
  String galleryReadError(String error) {
    return 'Gallery read failed\n$error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get permissionNeededTitle => 'Gallery access required';

  @override
  String get permissionDeniedTitle => 'Permission denied';

  @override
  String get permissionNeededBody =>
      'Liveback needs access to read Motion Photos from your gallery. Files are processed on-device and never uploaded.';

  @override
  String get permissionDeniedBody =>
      'Enable \"Photos and videos\" permission for Liveback in system settings, then return here.';

  @override
  String get permissionCta => 'Grant permission';

  @override
  String get permissionOpenSettings => 'Open settings';

  @override
  String confirmBarStart(int count) {
    return '$count Motion Photos · Start fixing';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get startFix => 'Start fixing';

  @override
  String get badgeAlreadySamsung => 'Already Samsung';

  @override
  String get badgeNeedsFix => 'Needs fix';

  @override
  String get tasksTitleProcessing => 'Processing';

  @override
  String get tasksTitleDone => 'Done';

  @override
  String tasksProgressRatio(int processed, int total) {
    return '$processed / $total';
  }

  @override
  String get tasksCancelAllTooltip => 'Cancel all tasks';

  @override
  String get tasksProcessingSnack => 'Processing — please wait';

  @override
  String get tasksEmpty => 'No tasks';

  @override
  String get tasksKeepAppOpen => 'Keep the app open until complete';

  @override
  String get tasksPickMore => 'Pick more';

  @override
  String tasksShareAll(int count) {
    return 'Share all ($count)';
  }

  @override
  String get tasksCancelAllTitle => 'Cancel all tasks?';

  @override
  String get tasksCancelAllBody =>
      'Completed files are kept. Queued tasks will be discarded.';

  @override
  String get tasksCancelAllKeep => 'Keep processing';

  @override
  String get tasksCancelAllConfirm => 'Cancel all';

  @override
  String get tasksLongVideoInline => 'Long video — WeChat may not recognize it';

  @override
  String get taskStatusWaiting => 'Waiting';

  @override
  String get taskStatusProcessing => 'Processing…';

  @override
  String taskStatusCompleted(String elapsed) {
    return 'Fixed · $elapsed';
  }

  @override
  String get taskStatusFailed => 'Fix failed';

  @override
  String taskStatusFailedWithCode(String code) {
    return 'Fix failed · $code';
  }

  @override
  String get taskStatusCancelled => 'Cancelled';

  @override
  String get taskStatusSkippedAlreadySamsung =>
      'Already in Samsung format — no fix needed';

  @override
  String get taskStatusSkippedNotMotionPhoto => 'Not a Motion Photo — skipped';

  @override
  String get taskPhaseParsing => 'Parsing';

  @override
  String get taskPhaseInjectingSef => 'Injecting SEF';

  @override
  String get taskPhaseWriting => 'Writing';

  @override
  String get errorDialogDefaultFailureTitle => 'Fix failed';

  @override
  String get errorDialogDefaultFailureBody =>
      'Processing failed. Please try again later.';

  @override
  String get errorDialogBack => 'Back';

  @override
  String get errorDialogRetry => 'Retry';

  @override
  String get resultNotFound => 'Task not found';

  @override
  String get resultTitleCompleted => 'Fixed';

  @override
  String get resultSubtitleCompleted =>
      'Samsung-compatible Motion Photo generated';

  @override
  String get resultTitleFailed => 'Fix failed';

  @override
  String get resultSubtitleFailedFallback =>
      'Processing failed. Please try again later.';

  @override
  String get resultTitleCancelled => 'Cancelled';

  @override
  String get resultSubtitleCancelled => 'This task was cancelled';

  @override
  String get resultTitleSkippedAlreadySamsung => 'No fix needed';

  @override
  String get resultSubtitleSkippedAlreadySamsung =>
      'This file is already in Samsung SEF format and can be sent to WeChat directly';

  @override
  String get resultTitleSkippedNotMotionPhoto => 'Not a Motion Photo';

  @override
  String get resultSubtitleSkippedNotMotionPhoto =>
      'This file is not a Motion Photo — no video segment to inject';

  @override
  String get resultTitleProcessing => 'Processing';

  @override
  String get resultWaveBefore => 'Before';

  @override
  String get resultWaveAfter => 'After';

  @override
  String get resultOutputPath => 'Output: Pictures/Liveback/';

  @override
  String get resultLongVideoWarn =>
      'Video >3s — WeChat may treat it as a still photo';

  @override
  String get resultBackToList => 'Back to list';

  @override
  String get resultShareWeChat => 'Share to WeChat';

  @override
  String get shareNoWeChat => 'WeChat not installed';

  @override
  String shareFailed(String error) {
    return 'Share failed: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguageHeader => '语言 / Language';

  @override
  String get settingsLanguageDescription =>
      'Change the app language. System follows your device locale.';

  @override
  String get languagePickerSystem => 'System';

  @override
  String get languagePickerEn => 'English';

  @override
  String get languagePickerZh => '中文 (Chinese)';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeHeader => 'Theme';

  @override
  String get settingsThemeDescription =>
      'Follows system by default. Pin to light or dark if preferred.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsNotificationSection => 'Notifications';

  @override
  String get settingsNotifRowLabel => 'Batch completion notification';

  @override
  String get settingsNotifRowSub => 'Notify when a batch finishes processing';

  @override
  String get settingsStorageSection => 'Storage';

  @override
  String get settingsClearCacheLabel => 'Clear cache';

  @override
  String get settingsClearCacheSub =>
      'Clears gallery thumbnail cache. Output files are not affected.';

  @override
  String get settingsToolsSection => 'Tools';

  @override
  String get settingsTestModeLabel => 'Self-test';

  @override
  String get settingsTestModeSub =>
      'Validates the binary fix chain against a bundled sample';

  @override
  String get settingsDialogPreviewSection => 'Dialog preview (dev)';

  @override
  String get settingsDlgInfoLabel => 'Info · first-run warning';

  @override
  String get settingsDlgInfoSub =>
      'Shown on first tap of the process button. Can be dismissed permanently.';

  @override
  String get settingsDlgConfirmLabel => 'Confirm · destructive action';

  @override
  String get settingsDlgConfirmSub =>
      'Secondary confirmation, e.g. cancel all tasks';

  @override
  String get settingsDlgErrorLabel => 'Error · detail view';

  @override
  String get settingsDlgErrorSub =>
      'Shown when the user taps a failed task to see the reason';

  @override
  String get settingsDlgInfoTitle => 'Processing heads-up';

  @override
  String get settingsDlgInfoBody =>
      'Keep the app open while processing. Queued tasks are lost if you switch away. You\'ll be notified when the batch completes.';

  @override
  String get settingsDlgInfoCheckbox => 'Don\'t show again';

  @override
  String get dialogInfoConfirm => 'Got it';

  @override
  String get dialogConfirmDefault => 'Confirm';

  @override
  String get dialogConfirmDefaultCancel => 'Cancel';

  @override
  String get settingsDlgErrorBody =>
      'The file was locked by another process while writing the SEF trailer. Close any preview tools and retry, or check storage permissions.';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsVersionLabel => 'Version';

  @override
  String get settingsFooter => 'All processing is local. No network access.';

  @override
  String get settingsClearCacheTitle => 'Clear gallery thumbnail cache?';

  @override
  String get settingsClearCacheBody =>
      'Only preview thumbnails are cleared. Output files are not affected.';

  @override
  String get settingsClearCacheCleared => 'Cleared';

  @override
  String get settingsClearCacheConfirm => 'Clear';

  @override
  String get testModeTitle => 'Self-test';

  @override
  String get testModeSampleSection => 'Test sample';

  @override
  String get testModeSampleDuration => '7.44 MB · 2.8s';

  @override
  String get testModeRunning => 'Running…';

  @override
  String get testModeRun => 'Run self-test';

  @override
  String get testModeRunAgain => 'Run again';

  @override
  String get testModeShare => 'Share test result to WeChat';

  @override
  String get testModeShareUnavailable =>
      'No output to share yet (waiting for real pipeline)';

  @override
  String get testModeStepParse => 'Parse JPEG';

  @override
  String get testModeStepDetectMp4 => 'Detect MP4 segment';

  @override
  String get testModeStepInjectSef => 'Inject SEF trailer';

  @override
  String get testModeStepFakeExif => 'Spoof EXIF';

  @override
  String get testModeStepWriteOutput => 'Write output';

  @override
  String get previewTooLarge => 'File too large to preview';

  @override
  String get previewLoadFailed => 'Load failed';

  @override
  String get previewNoVideo => 'No embedded video';

  @override
  String get previewDecodeFailed => 'Video decode failed';

  @override
  String get notificationChannelName => 'Batch complete';

  @override
  String get notificationChannelDescription =>
      'Sent when Liveback finishes processing a batch of Motion Photos';

  @override
  String get notificationBatchDefault => 'Batch complete';

  @override
  String notificationBatchFragmentSuccess(int count) {
    return '$count fixed';
  }

  @override
  String notificationBatchFragmentFailed(int count) {
    return '$count failed';
  }

  @override
  String notificationBatchFragmentSkipped(int count) {
    return '$count skipped';
  }

  @override
  String notificationBatchJoin(String parts) {
    return '$parts';
  }

  @override
  String get errJpegParse => 'File format error — may not be a valid JPEG.';

  @override
  String errJpegParseDetail(String detail) {
    return 'File format error — may not be a valid JPEG ($detail).';
  }

  @override
  String get errFileTooLarge => 'File too large (>2 GB). Trim the video first.';

  @override
  String get errApp1Overflow => 'File metadata too large to rewrite safely.';

  @override
  String get errSefWriteFail => 'Write failed. Check available storage.';

  @override
  String get errWriteCorrupt =>
      'Write interrupted — output file is incomplete.';

  @override
  String get errPermission => 'Storage or notification permission not granted.';

  @override
  String get errAlreadySamsung => 'Already in Samsung format — no fix needed.';

  @override
  String get errNoMp4 => 'Not a Motion Photo — no video segment to inject.';

  @override
  String get errUnknown => 'Processing failed. Please try again later.';
}
