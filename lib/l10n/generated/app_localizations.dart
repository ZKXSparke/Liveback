import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n? of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n);
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// 品牌名 — 不翻译。
  ///
  /// In zh, this message translates to:
  /// **'Liveback'**
  String get appName;

  /// Error banner when TaskQueue bootstrap throws. English passthrough — developer-facing, not localized.
  ///
  /// In zh, this message translates to:
  /// **'TaskQueue init failed: {error}'**
  String bootstrapTaskQueueFailed(String error);

  /// Home masthead first line (includes trailing newline).
  ///
  /// In zh, this message translates to:
  /// **'让实况图\n'**
  String get homeMastheadLine1;

  /// Dimmed emphasis word.
  ///
  /// In zh, this message translates to:
  /// **'重新'**
  String get homeMastheadEmphasis;

  /// Masthead tail after emphasis.
  ///
  /// In zh, this message translates to:
  /// **'动起来'**
  String get homeMastheadTail;

  /// No description provided for @homePrimaryCta.
  ///
  /// In zh, this message translates to:
  /// **'选择实况图'**
  String get homePrimaryCta;

  /// No description provided for @homePrimaryCtaSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'最多 100 张批量处理'**
  String get homePrimaryCtaSubtitle;

  /// No description provided for @statusChipReady.
  ///
  /// In zh, this message translates to:
  /// **'READY'**
  String get statusChipReady;

  /// No description provided for @statusChipSyncing.
  ///
  /// In zh, this message translates to:
  /// **'SYNCING'**
  String get statusChipSyncing;

  /// No description provided for @statusChipError.
  ///
  /// In zh, this message translates to:
  /// **'ERROR'**
  String get statusChipError;

  /// No description provided for @fixedCounterLabel.
  ///
  /// In zh, this message translates to:
  /// **'FIXED'**
  String get fixedCounterLabel;

  /// No description provided for @localOfflineLabel.
  ///
  /// In zh, this message translates to:
  /// **'LOCAL · OFFLINE'**
  String get localOfflineLabel;

  /// No description provided for @galleryTitleSelect.
  ///
  /// In zh, this message translates to:
  /// **'选择实况图'**
  String get galleryTitleSelect;

  /// No description provided for @galleryTitleAllAlbums.
  ///
  /// In zh, this message translates to:
  /// **'全部相册'**
  String get galleryTitleAllAlbums;

  /// Confirm button label showing selection state.
  ///
  /// In zh, this message translates to:
  /// **'完成 · {selection}'**
  String galleryDoneButton(String selection);

  /// No description provided for @gallerySelectionRatio.
  ///
  /// In zh, this message translates to:
  /// **'{selected}/{max}'**
  String gallerySelectionRatio(int selected, int max);

  /// No description provided for @gallerySelectionHidden.
  ///
  /// In zh, this message translates to:
  /// **'{selected}/{max} · +{hidden} 张已选但隐藏'**
  String gallerySelectionHidden(int selected, int max, int hidden);

  /// No description provided for @filterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get filterAll;

  /// No description provided for @filterMotionOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅显示实况图'**
  String get filterMotionOnly;

  /// No description provided for @filterNeedsFix.
  ///
  /// In zh, this message translates to:
  /// **'待修复'**
  String get filterNeedsFix;

  /// No description provided for @albumPickerTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择相册'**
  String get albumPickerTitle;

  /// No description provided for @albumPickerAllAlbums.
  ///
  /// In zh, this message translates to:
  /// **'全部相册'**
  String get albumPickerAllAlbums;

  /// No description provided for @albumPickerEmpty.
  ///
  /// In zh, this message translates to:
  /// **'图库里没有相册'**
  String get albumPickerEmpty;

  /// No description provided for @albumPickerCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张'**
  String albumPickerCount(int count);

  /// No description provided for @galleryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'图库里没有图片'**
  String get galleryEmptyTitle;

  /// No description provided for @galleryEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'拍摄实况图或从相册导入后再来'**
  String get galleryEmptyBody;

  /// No description provided for @galleryFilteredEmptyAll.
  ///
  /// In zh, this message translates to:
  /// **'这个相册里没有图片'**
  String get galleryFilteredEmptyAll;

  /// No description provided for @galleryFilteredEmptyMotion.
  ///
  /// In zh, this message translates to:
  /// **'没有符合条件的实况图'**
  String get galleryFilteredEmptyMotion;

  /// No description provided for @galleryFilteredEmptyNeedsFix.
  ///
  /// In zh, this message translates to:
  /// **'没有待修复的实况图'**
  String get galleryFilteredEmptyNeedsFix;

  /// No description provided for @galleryNoMore.
  ///
  /// In zh, this message translates to:
  /// **'没有更多图片了'**
  String get galleryNoMore;

  /// No description provided for @galleryNoMoreFiltered.
  ///
  /// In zh, this message translates to:
  /// **'没有更多符合条件的图片'**
  String get galleryNoMoreFiltered;

  /// No description provided for @galleryReadError.
  ///
  /// In zh, this message translates to:
  /// **'图库读取失败\n{error}'**
  String galleryReadError(String error);

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @permissionNeededTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要图库访问权限'**
  String get permissionNeededTitle;

  /// No description provided for @permissionDeniedTitle.
  ///
  /// In zh, this message translates to:
  /// **'权限已关闭'**
  String get permissionDeniedTitle;

  /// No description provided for @permissionNeededBody.
  ///
  /// In zh, this message translates to:
  /// **'读取你相册里的实况图，才能送去修复。权限只用于本机解析，不上传。'**
  String get permissionNeededBody;

  /// No description provided for @permissionDeniedBody.
  ///
  /// In zh, this message translates to:
  /// **'在系统设置里给 Liveback 开启\"照片和视频\"权限后再回到这里。'**
  String get permissionDeniedBody;

  /// No description provided for @permissionCta.
  ///
  /// In zh, this message translates to:
  /// **'授予权限'**
  String get permissionCta;

  /// No description provided for @permissionOpenSettings.
  ///
  /// In zh, this message translates to:
  /// **'去系统设置'**
  String get permissionOpenSettings;

  /// No description provided for @confirmBarStart.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张实况图 · 开始修复'**
  String confirmBarStart(int count);

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @startFix.
  ///
  /// In zh, this message translates to:
  /// **'开始修复'**
  String get startFix;

  /// No description provided for @badgeAlreadySamsung.
  ///
  /// In zh, this message translates to:
  /// **'已是三星'**
  String get badgeAlreadySamsung;

  /// No description provided for @badgeNeedsFix.
  ///
  /// In zh, this message translates to:
  /// **'待修复'**
  String get badgeNeedsFix;

  /// No description provided for @tasksTitleProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get tasksTitleProcessing;

  /// No description provided for @tasksTitleDone.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get tasksTitleDone;

  /// No description provided for @tasksProgressRatio.
  ///
  /// In zh, this message translates to:
  /// **'{processed} / {total}'**
  String tasksProgressRatio(int processed, int total);

  /// No description provided for @tasksCancelAllTooltip.
  ///
  /// In zh, this message translates to:
  /// **'取消全部任务'**
  String get tasksCancelAllTooltip;

  /// No description provided for @tasksProcessingSnack.
  ///
  /// In zh, this message translates to:
  /// **'处理中，请耐心等待'**
  String get tasksProcessingSnack;

  /// No description provided for @tasksEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无任务'**
  String get tasksEmpty;

  /// No description provided for @tasksKeepAppOpen.
  ///
  /// In zh, this message translates to:
  /// **'请保持应用打开直至完成'**
  String get tasksKeepAppOpen;

  /// No description provided for @tasksPickMore.
  ///
  /// In zh, this message translates to:
  /// **'再来一批'**
  String get tasksPickMore;

  /// No description provided for @tasksShareAll.
  ///
  /// In zh, this message translates to:
  /// **'分享全部 ({count})'**
  String tasksShareAll(int count);

  /// No description provided for @tasksCancelAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'取消全部任务？'**
  String get tasksCancelAllTitle;

  /// No description provided for @tasksCancelAllBody.
  ///
  /// In zh, this message translates to:
  /// **'已处理完成的文件会保留，未开始的会被丢弃。'**
  String get tasksCancelAllBody;

  /// No description provided for @tasksCancelAllKeep.
  ///
  /// In zh, this message translates to:
  /// **'继续处理'**
  String get tasksCancelAllKeep;

  /// No description provided for @tasksCancelAllConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认取消'**
  String get tasksCancelAllConfirm;

  /// No description provided for @tasksLongVideoInline.
  ///
  /// In zh, this message translates to:
  /// **'视频较长，可能识别失败'**
  String get tasksLongVideoInline;

  /// No description provided for @taskStatusWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get taskStatusWaiting;

  /// No description provided for @taskStatusProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中…'**
  String get taskStatusProcessing;

  /// No description provided for @taskStatusCompleted.
  ///
  /// In zh, this message translates to:
  /// **'修复完成 · {elapsed}'**
  String taskStatusCompleted(String elapsed);

  /// No description provided for @taskStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'修复失败'**
  String get taskStatusFailed;

  /// No description provided for @taskStatusFailedWithCode.
  ///
  /// In zh, this message translates to:
  /// **'修复失败 · {code}'**
  String taskStatusFailedWithCode(String code);

  /// No description provided for @taskStatusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get taskStatusCancelled;

  /// No description provided for @taskStatusSkippedAlreadySamsung.
  ///
  /// In zh, this message translates to:
  /// **'已是三星格式，无需修复'**
  String get taskStatusSkippedAlreadySamsung;

  /// No description provided for @taskStatusSkippedNotMotionPhoto.
  ///
  /// In zh, this message translates to:
  /// **'不是实况图，已跳过'**
  String get taskStatusSkippedNotMotionPhoto;

  /// No description provided for @taskPhaseParsing.
  ///
  /// In zh, this message translates to:
  /// **'解析中'**
  String get taskPhaseParsing;

  /// No description provided for @taskPhaseInjectingSef.
  ///
  /// In zh, this message translates to:
  /// **'注入 SEF'**
  String get taskPhaseInjectingSef;

  /// No description provided for @taskPhaseWriting.
  ///
  /// In zh, this message translates to:
  /// **'写入中'**
  String get taskPhaseWriting;

  /// No description provided for @errorDialogDefaultFailureTitle.
  ///
  /// In zh, this message translates to:
  /// **'修复失败'**
  String get errorDialogDefaultFailureTitle;

  /// No description provided for @errorDialogDefaultFailureBody.
  ///
  /// In zh, this message translates to:
  /// **'处理失败，请稍后重试'**
  String get errorDialogDefaultFailureBody;

  /// No description provided for @errorDialogBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get errorDialogBack;

  /// No description provided for @errorDialogRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get errorDialogRetry;

  /// No description provided for @resultNotFound.
  ///
  /// In zh, this message translates to:
  /// **'任务不存在'**
  String get resultNotFound;

  /// No description provided for @resultTitleCompleted.
  ///
  /// In zh, this message translates to:
  /// **'修复完成'**
  String get resultTitleCompleted;

  /// No description provided for @resultSubtitleCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已生成三星兼容的 Motion Photo'**
  String get resultSubtitleCompleted;

  /// No description provided for @resultTitleFailed.
  ///
  /// In zh, this message translates to:
  /// **'修复失败'**
  String get resultTitleFailed;

  /// No description provided for @resultSubtitleFailedFallback.
  ///
  /// In zh, this message translates to:
  /// **'处理失败，请稍后重试'**
  String get resultSubtitleFailedFallback;

  /// No description provided for @resultTitleCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get resultTitleCancelled;

  /// No description provided for @resultSubtitleCancelled.
  ///
  /// In zh, this message translates to:
  /// **'此任务已被取消'**
  String get resultSubtitleCancelled;

  /// No description provided for @resultTitleSkippedAlreadySamsung.
  ///
  /// In zh, this message translates to:
  /// **'无需修复'**
  String get resultTitleSkippedAlreadySamsung;

  /// No description provided for @resultSubtitleSkippedAlreadySamsung.
  ///
  /// In zh, this message translates to:
  /// **'此文件已是三星 SEF 格式，可以直接发送到微信'**
  String get resultSubtitleSkippedAlreadySamsung;

  /// No description provided for @resultTitleSkippedNotMotionPhoto.
  ///
  /// In zh, this message translates to:
  /// **'不是实况图'**
  String get resultTitleSkippedNotMotionPhoto;

  /// No description provided for @resultSubtitleSkippedNotMotionPhoto.
  ///
  /// In zh, this message translates to:
  /// **'此文件不是实况图，没有可注入的视频段'**
  String get resultSubtitleSkippedNotMotionPhoto;

  /// No description provided for @resultTitleProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get resultTitleProcessing;

  /// No description provided for @resultWaveBefore.
  ///
  /// In zh, this message translates to:
  /// **'修复前'**
  String get resultWaveBefore;

  /// No description provided for @resultWaveAfter.
  ///
  /// In zh, this message translates to:
  /// **'修复后'**
  String get resultWaveAfter;

  /// No description provided for @resultOutputPath.
  ///
  /// In zh, this message translates to:
  /// **'输出: Pictures/Liveback/'**
  String get resultOutputPath;

  /// No description provided for @resultLongVideoWarn.
  ///
  /// In zh, this message translates to:
  /// **'视频 >3s，微信可能识别为普通图片'**
  String get resultLongVideoWarn;

  /// No description provided for @resultBackToList.
  ///
  /// In zh, this message translates to:
  /// **'返回列表'**
  String get resultBackToList;

  /// No description provided for @resultShareWeChat.
  ///
  /// In zh, this message translates to:
  /// **'分享到微信'**
  String get resultShareWeChat;

  /// No description provided for @shareNoWeChat.
  ///
  /// In zh, this message translates to:
  /// **'未安装微信'**
  String get shareNoWeChat;

  /// No description provided for @shareFailed.
  ///
  /// In zh, this message translates to:
  /// **'分享失败: {error}'**
  String shareFailed(String error);

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageHeader.
  ///
  /// In zh, this message translates to:
  /// **'语言 / Language'**
  String get settingsLanguageHeader;

  /// No description provided for @settingsLanguageDescription.
  ///
  /// In zh, this message translates to:
  /// **'切换应用语言。跟随系统则与设备语言一致。'**
  String get settingsLanguageDescription;

  /// No description provided for @languagePickerSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languagePickerSystem;

  /// No description provided for @languagePickerEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languagePickerEn;

  /// No description provided for @languagePickerZh.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get languagePickerZh;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeHeader.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsThemeHeader;

  /// No description provided for @settingsThemeDescription.
  ///
  /// In zh, this message translates to:
  /// **'默认跟随系统切换深浅色；可强制固定其中一种'**
  String get settingsThemeDescription;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @settingsNotificationSection.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get settingsNotificationSection;

  /// No description provided for @settingsNotifRowLabel.
  ///
  /// In zh, this message translates to:
  /// **'完成后系统通知'**
  String get settingsNotifRowLabel;

  /// No description provided for @settingsNotifRowSub.
  ///
  /// In zh, this message translates to:
  /// **'批次处理完成时推送通知'**
  String get settingsNotifRowSub;

  /// No description provided for @settingsStorageSection.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get settingsStorageSection;

  /// No description provided for @settingsClearCacheLabel.
  ///
  /// In zh, this message translates to:
  /// **'清除缓存'**
  String get settingsClearCacheLabel;

  /// No description provided for @settingsClearCacheSub.
  ///
  /// In zh, this message translates to:
  /// **'清理画廊缩略图缓存，不会删除输出文件'**
  String get settingsClearCacheSub;

  /// No description provided for @settingsToolsSection.
  ///
  /// In zh, this message translates to:
  /// **'工具'**
  String get settingsToolsSection;

  /// No description provided for @settingsTestModeLabel.
  ///
  /// In zh, this message translates to:
  /// **'自检'**
  String get settingsTestModeLabel;

  /// No description provided for @settingsTestModeSub.
  ///
  /// In zh, this message translates to:
  /// **'用内置样本验证格式修复链路'**
  String get settingsTestModeSub;

  /// No description provided for @settingsDialogPreviewSection.
  ///
  /// In zh, this message translates to:
  /// **'弹窗预览（开发调试）'**
  String get settingsDialogPreviewSection;

  /// No description provided for @settingsDlgInfoLabel.
  ///
  /// In zh, this message translates to:
  /// **'信息 · 首次警告'**
  String get settingsDlgInfoLabel;

  /// No description provided for @settingsDlgInfoSub.
  ///
  /// In zh, this message translates to:
  /// **'首次点击处理按钮弹出，可勾选不再提醒'**
  String get settingsDlgInfoSub;

  /// No description provided for @settingsDlgConfirmLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认 · 危险操作'**
  String get settingsDlgConfirmLabel;

  /// No description provided for @settingsDlgConfirmSub.
  ///
  /// In zh, this message translates to:
  /// **'例如取消全部任务的二次确认'**
  String get settingsDlgConfirmSub;

  /// No description provided for @settingsDlgErrorLabel.
  ///
  /// In zh, this message translates to:
  /// **'错误 · 详情'**
  String get settingsDlgErrorLabel;

  /// No description provided for @settingsDlgErrorSub.
  ///
  /// In zh, this message translates to:
  /// **'用户点击失败任务查看原因'**
  String get settingsDlgErrorSub;

  /// No description provided for @settingsDlgInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'处理过程提示'**
  String get settingsDlgInfoTitle;

  /// No description provided for @settingsDlgInfoBody.
  ///
  /// In zh, this message translates to:
  /// **'处理期间请不要切走应用，否则已排队的任务会丢失。处理完成后会自动通知。'**
  String get settingsDlgInfoBody;

  /// No description provided for @settingsDlgInfoCheckbox.
  ///
  /// In zh, this message translates to:
  /// **'不再提醒'**
  String get settingsDlgInfoCheckbox;

  /// No description provided for @dialogInfoConfirm.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get dialogInfoConfirm;

  /// No description provided for @dialogConfirmDefault.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get dialogConfirmDefault;

  /// No description provided for @dialogConfirmDefaultCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get dialogConfirmDefaultCancel;

  /// No description provided for @settingsDlgErrorBody.
  ///
  /// In zh, this message translates to:
  /// **'写入 SEF trailer 时文件被其他程序占用，请关闭预览工具后重试，或检查存储权限。'**
  String get settingsDlgErrorBody;

  /// No description provided for @settingsAboutSection.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAboutSection;

  /// No description provided for @settingsVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get settingsVersionLabel;

  /// No description provided for @settingsFooter.
  ///
  /// In zh, this message translates to:
  /// **'本应用纯本地处理，不联网'**
  String get settingsFooter;

  /// No description provided for @settingsClearCacheTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除画廊缩略图缓存？'**
  String get settingsClearCacheTitle;

  /// No description provided for @settingsClearCacheBody.
  ///
  /// In zh, this message translates to:
  /// **'这只会清除画廊预览的缩略图，不会影响输出文件。'**
  String get settingsClearCacheBody;

  /// No description provided for @settingsClearCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除'**
  String get settingsClearCacheCleared;

  /// No description provided for @settingsClearCacheConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get settingsClearCacheConfirm;

  /// No description provided for @testModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'自检'**
  String get testModeTitle;

  /// No description provided for @testModeSampleSection.
  ///
  /// In zh, this message translates to:
  /// **'测试样本'**
  String get testModeSampleSection;

  /// No description provided for @testModeSampleDuration.
  ///
  /// In zh, this message translates to:
  /// **'7.44 MB · 2.8s'**
  String get testModeSampleDuration;

  /// No description provided for @testModeRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中…'**
  String get testModeRunning;

  /// No description provided for @testModeRun.
  ///
  /// In zh, this message translates to:
  /// **'运行自检'**
  String get testModeRun;

  /// No description provided for @testModeRunAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新运行'**
  String get testModeRunAgain;

  /// No description provided for @testModeShare.
  ///
  /// In zh, this message translates to:
  /// **'分享测试结果到微信'**
  String get testModeShare;

  /// No description provided for @testModeShareUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'尚无可分享的输出（等待真实管线接入）'**
  String get testModeShareUnavailable;

  /// No description provided for @testModeStepParse.
  ///
  /// In zh, this message translates to:
  /// **'解析 JPEG'**
  String get testModeStepParse;

  /// No description provided for @testModeStepDetectMp4.
  ///
  /// In zh, this message translates to:
  /// **'检测 MP4 段'**
  String get testModeStepDetectMp4;

  /// No description provided for @testModeStepInjectSef.
  ///
  /// In zh, this message translates to:
  /// **'注入 SEF trailer'**
  String get testModeStepInjectSef;

  /// No description provided for @testModeStepFakeExif.
  ///
  /// In zh, this message translates to:
  /// **'伪装 EXIF'**
  String get testModeStepFakeExif;

  /// No description provided for @testModeStepWriteOutput.
  ///
  /// In zh, this message translates to:
  /// **'写入输出'**
  String get testModeStepWriteOutput;

  /// No description provided for @previewTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件过大，无法预览'**
  String get previewTooLarge;

  /// No description provided for @previewLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get previewLoadFailed;

  /// No description provided for @previewNoVideo.
  ///
  /// In zh, this message translates to:
  /// **'该图片无视频段'**
  String get previewNoVideo;

  /// No description provided for @previewDecodeFailed.
  ///
  /// In zh, this message translates to:
  /// **'视频解码失败'**
  String get previewDecodeFailed;

  /// No description provided for @notificationChannelName.
  ///
  /// In zh, this message translates to:
  /// **'批次处理完成'**
  String get notificationChannelName;

  /// No description provided for @notificationChannelDescription.
  ///
  /// In zh, this message translates to:
  /// **'Liveback 处理一批实况图后推送'**
  String get notificationChannelDescription;

  /// No description provided for @notificationBatchDefault.
  ///
  /// In zh, this message translates to:
  /// **'批次处理完成'**
  String get notificationBatchDefault;

  /// No description provided for @notificationBatchFragmentSuccess.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张已修复'**
  String notificationBatchFragmentSuccess(int count);

  /// No description provided for @notificationBatchFragmentFailed.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张失败'**
  String notificationBatchFragmentFailed(int count);

  /// No description provided for @notificationBatchFragmentSkipped.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张跳过'**
  String notificationBatchFragmentSkipped(int count);

  /// Passthrough container so the joined string goes through the ARB pipeline.
  ///
  /// In zh, this message translates to:
  /// **'{parts}'**
  String notificationBatchJoin(String parts);

  /// No description provided for @errJpegParse.
  ///
  /// In zh, this message translates to:
  /// **'文件格式错误，可能不是有效的 JPEG'**
  String get errJpegParse;

  /// No description provided for @errJpegParseDetail.
  ///
  /// In zh, this message translates to:
  /// **'文件格式错误，可能不是有效的 JPEG（{detail}）'**
  String errJpegParseDetail(String detail);

  /// No description provided for @errFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件太大（>2GB），请先裁剪视频'**
  String get errFileTooLarge;

  /// No description provided for @errApp1Overflow.
  ///
  /// In zh, this message translates to:
  /// **'文件元数据过大，无法安全重写'**
  String get errApp1Overflow;

  /// No description provided for @errSefWriteFail.
  ///
  /// In zh, this message translates to:
  /// **'写入失败，请检查存储空间'**
  String get errSefWriteFail;

  /// No description provided for @errWriteCorrupt.
  ///
  /// In zh, this message translates to:
  /// **'写入中断，输出文件不完整'**
  String get errWriteCorrupt;

  /// No description provided for @errPermission.
  ///
  /// In zh, this message translates to:
  /// **'未获得存储或通知权限'**
  String get errPermission;

  /// No description provided for @errAlreadySamsung.
  ///
  /// In zh, this message translates to:
  /// **'已是三星格式，无需修复'**
  String get errAlreadySamsung;

  /// No description provided for @errNoMp4.
  ///
  /// In zh, this message translates to:
  /// **'不是实况图，没有可注入的视频段'**
  String get errNoMp4;

  /// No description provided for @errUnknown.
  ///
  /// In zh, this message translates to:
  /// **'处理失败，请稍后重试'**
  String get errUnknown;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
      'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
