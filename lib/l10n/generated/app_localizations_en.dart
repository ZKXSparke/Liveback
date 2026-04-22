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
  String get homeMastheadLine1 => '让实况图\n';

  @override
  String get homeMastheadEmphasis => '重新';

  @override
  String get homeMastheadTail => '动起来';

  @override
  String get homePrimaryCta => '选择实况图';

  @override
  String get homePrimaryCtaSubtitle => '最多 100 张批量处理';

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
  String get galleryTitleSelect => '选择实况图';

  @override
  String get galleryTitleAllAlbums => '全部相册';

  @override
  String galleryDoneButton(String selection) {
    return '完成 · $selection';
  }

  @override
  String gallerySelectionRatio(int selected, int max) {
    return '$selected/$max';
  }

  @override
  String gallerySelectionHidden(int selected, int max, int hidden) {
    return '$selected/$max · +$hidden 张已选但隐藏';
  }

  @override
  String get filterAll => '全部';

  @override
  String get filterMotionOnly => '仅显示实况图';

  @override
  String get filterNeedsFix => '待修复';

  @override
  String get albumPickerTitle => '选择相册';

  @override
  String get albumPickerAllAlbums => '全部相册';

  @override
  String get albumPickerEmpty => '图库里没有相册';

  @override
  String albumPickerCount(int count) {
    return '$count 张';
  }

  @override
  String get galleryEmptyTitle => '图库里没有图片';

  @override
  String get galleryEmptyBody => '拍摄实况图或从相册导入后再来';

  @override
  String get galleryFilteredEmptyAll => '这个相册里没有图片';

  @override
  String get galleryFilteredEmptyMotion => '没有符合条件的实况图';

  @override
  String get galleryFilteredEmptyNeedsFix => '没有待修复的实况图';

  @override
  String get galleryNoMore => '没有更多图片了';

  @override
  String get galleryNoMoreFiltered => '没有更多符合条件的图片';

  @override
  String galleryReadError(String error) {
    return '图库读取失败\n$error';
  }

  @override
  String get retry => '重试';

  @override
  String get permissionNeededTitle => '需要图库访问权限';

  @override
  String get permissionDeniedTitle => '权限已关闭';

  @override
  String get permissionNeededBody => '读取你相册里的实况图，才能送去修复。权限只用于本机解析，不上传。';

  @override
  String get permissionDeniedBody => '在系统设置里给 Liveback 开启\"照片和视频\"权限后再回到这里。';

  @override
  String get permissionCta => '授予权限';

  @override
  String get permissionOpenSettings => '去系统设置';

  @override
  String confirmBarStart(int count) {
    return '$count 张实况图 · 开始修复';
  }

  @override
  String get cancel => '取消';

  @override
  String get startFix => '开始修复';

  @override
  String get badgeAlreadySamsung => '已是三星';

  @override
  String get badgeNeedsFix => '待修复';

  @override
  String get tasksTitleProcessing => '处理中';

  @override
  String get tasksTitleDone => '已完成';

  @override
  String tasksProgressRatio(int processed, int total) {
    return '$processed / $total';
  }

  @override
  String get tasksCancelAllTooltip => '取消全部任务';

  @override
  String get tasksProcessingSnack => '处理中，请耐心等待';

  @override
  String get tasksEmpty => '暂无任务';

  @override
  String get tasksKeepAppOpen => '请保持应用打开直至完成';

  @override
  String get tasksPickMore => '再来一批';

  @override
  String tasksShareAll(int count) {
    return '分享全部 ($count)';
  }

  @override
  String get tasksCancelAllTitle => '取消全部任务？';

  @override
  String get tasksCancelAllBody => '已处理完成的文件会保留，未开始的会被丢弃。';

  @override
  String get tasksCancelAllKeep => '继续处理';

  @override
  String get tasksCancelAllConfirm => '确认取消';

  @override
  String get tasksLongVideoInline => '视频较长，可能识别失败';

  @override
  String get taskStatusWaiting => '等待中';

  @override
  String get taskStatusProcessing => '处理中…';

  @override
  String taskStatusCompleted(String elapsed) {
    return '修复完成 · $elapsed';
  }

  @override
  String get taskStatusFailed => '修复失败';

  @override
  String taskStatusFailedWithCode(String code) {
    return '修复失败 · $code';
  }

  @override
  String get taskStatusCancelled => '已取消';

  @override
  String get taskStatusSkippedAlreadySamsung => '已是三星格式，无需修复';

  @override
  String get taskStatusSkippedNotMotionPhoto => '不是实况图，已跳过';

  @override
  String get taskPhaseParsing => '解析中';

  @override
  String get taskPhaseInjectingSef => '注入 SEF';

  @override
  String get taskPhaseWriting => '写入中';

  @override
  String get errorDialogDefaultFailureTitle => '修复失败';

  @override
  String get errorDialogDefaultFailureBody => '处理失败，请稍后重试';

  @override
  String get errorDialogBack => '返回';

  @override
  String get errorDialogRetry => '重试';

  @override
  String get resultNotFound => '任务不存在';

  @override
  String get resultTitleCompleted => '修复完成';

  @override
  String get resultSubtitleCompleted => '已生成三星兼容的 Motion Photo';

  @override
  String get resultTitleFailed => '修复失败';

  @override
  String get resultSubtitleFailedFallback => '处理失败，请稍后重试';

  @override
  String get resultTitleCancelled => '已取消';

  @override
  String get resultSubtitleCancelled => '此任务已被取消';

  @override
  String get resultTitleSkippedAlreadySamsung => '无需修复';

  @override
  String get resultSubtitleSkippedAlreadySamsung => '此文件已是三星 SEF 格式，可以直接发送到微信';

  @override
  String get resultTitleSkippedNotMotionPhoto => '不是实况图';

  @override
  String get resultSubtitleSkippedNotMotionPhoto => '此文件不是实况图，没有可注入的视频段';

  @override
  String get resultTitleProcessing => '处理中';

  @override
  String get resultWaveBefore => '修复前';

  @override
  String get resultWaveAfter => '修复后';

  @override
  String get resultOutputPath => '输出: Pictures/Liveback/';

  @override
  String get resultLongVideoWarn => '视频 >3s，微信可能识别为普通图片';

  @override
  String get resultBackToList => '返回列表';

  @override
  String get resultShareWeChat => '分享到微信';

  @override
  String get shareNoWeChat => '未安装微信';

  @override
  String shareFailed(String error) {
    return '分享失败: $error';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsLanguageSection => '语言';

  @override
  String get settingsLanguageHeader => '语言 / Language';

  @override
  String get settingsLanguageDescription => '切换应用语言。跟随系统则与设备语言一致。';

  @override
  String get languagePickerSystem => '跟随系统';

  @override
  String get languagePickerEn => 'English';

  @override
  String get languagePickerZh => '中文';

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsThemeHeader => '主题';

  @override
  String get settingsThemeDescription => '默认跟随系统切换深浅色；可强制固定其中一种';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get settingsNotificationSection => '通知';

  @override
  String get settingsNotifRowLabel => '完成后系统通知';

  @override
  String get settingsNotifRowSub => '批次处理完成时推送通知';

  @override
  String get settingsStorageSection => '存储';

  @override
  String get settingsClearCacheLabel => '清除缓存';

  @override
  String get settingsClearCacheSub => '清理画廊缩略图缓存，不会删除输出文件';

  @override
  String get settingsToolsSection => '工具';

  @override
  String get settingsTestModeLabel => '自检';

  @override
  String get settingsTestModeSub => '用内置样本验证格式修复链路';

  @override
  String get settingsDialogPreviewSection => '弹窗预览（开发调试）';

  @override
  String get settingsDlgInfoLabel => '信息 · 首次警告';

  @override
  String get settingsDlgInfoSub => '首次点击处理按钮弹出，可勾选不再提醒';

  @override
  String get settingsDlgConfirmLabel => '确认 · 危险操作';

  @override
  String get settingsDlgConfirmSub => '例如取消全部任务的二次确认';

  @override
  String get settingsDlgErrorLabel => '错误 · 详情';

  @override
  String get settingsDlgErrorSub => '用户点击失败任务查看原因';

  @override
  String get settingsDlgInfoTitle => '处理过程提示';

  @override
  String get settingsDlgInfoBody => '处理期间请不要切走应用，否则已排队的任务会丢失。处理完成后会自动通知。';

  @override
  String get settingsDlgInfoCheckbox => '不再提醒';

  @override
  String get dialogInfoConfirm => '知道了';

  @override
  String get dialogConfirmDefault => '确认';

  @override
  String get dialogConfirmDefaultCancel => '取消';

  @override
  String get settingsDlgErrorBody =>
      '写入 SEF trailer 时文件被其他程序占用，请关闭预览工具后重试，或检查存储权限。';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsVersionLabel => '版本';

  @override
  String get settingsFooter => '本应用纯本地处理，不联网';

  @override
  String get settingsClearCacheTitle => '清除画廊缩略图缓存？';

  @override
  String get settingsClearCacheBody => '这只会清除画廊预览的缩略图，不会影响输出文件。';

  @override
  String get settingsClearCacheCleared => '已清除';

  @override
  String get settingsClearCacheConfirm => '清除';

  @override
  String get testModeTitle => '自检';

  @override
  String get testModeSampleSection => '测试样本';

  @override
  String get testModeSampleDuration => '7.44 MB · 2.8s';

  @override
  String get testModeRunning => '运行中…';

  @override
  String get testModeRun => '运行自检';

  @override
  String get testModeRunAgain => '重新运行';

  @override
  String get testModeShare => '分享测试结果到微信';

  @override
  String get testModeShareUnavailable => '尚无可分享的输出（等待真实管线接入）';

  @override
  String get testModeStepParse => '解析 JPEG';

  @override
  String get testModeStepDetectMp4 => '检测 MP4 段';

  @override
  String get testModeStepInjectSef => '注入 SEF trailer';

  @override
  String get testModeStepFakeExif => '伪装 EXIF';

  @override
  String get testModeStepWriteOutput => '写入输出';

  @override
  String get previewTooLarge => '文件过大，无法预览';

  @override
  String get previewLoadFailed => '加载失败';

  @override
  String get previewNoVideo => '该图片无视频段';

  @override
  String get previewDecodeFailed => '视频解码失败';

  @override
  String get notificationChannelName => '批次处理完成';

  @override
  String get notificationChannelDescription => 'Liveback 处理一批实况图后推送';

  @override
  String get notificationBatchDefault => '批次处理完成';

  @override
  String notificationBatchFragmentSuccess(int count) {
    return '$count 张已修复';
  }

  @override
  String notificationBatchFragmentFailed(int count) {
    return '$count 张失败';
  }

  @override
  String notificationBatchFragmentSkipped(int count) {
    return '$count 张跳过';
  }

  @override
  String notificationBatchJoin(String parts) {
    return '$parts';
  }

  @override
  String get errJpegParse => '文件格式错误，可能不是有效的 JPEG';

  @override
  String errJpegParseDetail(String detail) {
    return '文件格式错误，可能不是有效的 JPEG（$detail）';
  }

  @override
  String get errFileTooLarge => '文件太大（>2GB），请先裁剪视频';

  @override
  String get errApp1Overflow => '文件元数据过大，无法安全重写';

  @override
  String get errSefWriteFail => '写入失败，请检查存储空间';

  @override
  String get errWriteCorrupt => '写入中断，输出文件不完整';

  @override
  String get errPermission => '未获得存储或通知权限';

  @override
  String get errAlreadySamsung => '已是三星格式，无需修复';

  @override
  String get errNoMp4 => '不是实况图，没有可注入的视频段';

  @override
  String get errUnknown => '处理失败，请稍后重试';
}
