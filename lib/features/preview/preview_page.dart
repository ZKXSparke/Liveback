// Owner: T3 (UI teammate). Reference: Doc 1 §5.2 routes + §7 animation.
//
// Full-screen preview for a gallery tile: letterboxed on brand-dark bg.
// Tap on a tile in the gallery → this page. On mount, after sandbox +
// parser resolve, if the file is a Motion Photo we AUTO-PLAY the MP4
// trailer ONCE (non-looping). When playback reaches its natural end,
// fade the video layer out and reveal the still underneath (~200 ms).
//
// A round play button appears bottom-center once the initial auto-play
// completes (or as a fallback if the probe resolved and the user hasn't
// long-pressed yet). Tapping it replays the video once, non-looping.
//
// Long-press-and-HOLD still works as before — it enters LOOPING playback
// for the duration of the hold (the "手指持续按住模拟 iOS 长按 Live
// Photo" metaphor). Release → stops, returns to still. Non-motion-photo
// long-press still surfaces the "无视频段" pill.
//
// Lifecycle:
//   initState → copyInputToSandbox + MotionPhotoParser.parse.
//   After parse resolves + isMotionPhoto → _extractAndPlay(looping:false)
//     auto-fires exactly once (_autoPlayTriggered guard).
//   On playback end detection (position ≥ duration − epsilon, or
//     !isPlaying after having played) the video layer fades out.
//   Round play button tap → _extractAndPlay(looping:false) (replay).
//   Long-press start → _extractAndPlay(looping:true) (or takes over an
//     already-initialised controller).
//   Long-press end → pause + seek(0). Still image still sits underneath.
//   dispose → dispose controller, delete extracted temp file, fire-and-
//     forget releaseSandbox.
//
// Memory: MP4 extraction streams through a 256 KB rolling buffer so the
// full JPEG never sits in Dart heap.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../l10n/l10n_ext.dart';
import '../../services/mediastore_channel.dart';
import '../../services/motion_photo_parser.dart';
import '../../widgets/theme_access.dart';
import 'extract_mp4_range.dart';

export 'extract_mp4_range.dart' show extractMp4Range;

/// Arguments for the `/preview` route.
class PreviewPageArgs {
  final String contentUri;
  final String displayName;
  final int sizeBytes;

  const PreviewPageArgs({
    required this.contentUri,
    required this.displayName,
    required this.sizeBytes,
  });
}

class PreviewPage extends StatefulWidget {
  final PreviewPageArgs args;

  const PreviewPage({super.key, required this.args});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final _channel = MediaStoreChannel();
  final _parser = MotionPhotoParser();

  // Sandbox + probe state.
  bool _sandboxReady = false;
  bool _probing = false;
  bool _oversized = false; // file exceeds max preview size
  String? _sandboxPath;
  String? _loadError;
  late final String _taskId;

  // Motion Photo probe result.
  bool _isMotionPhoto = false;
  int? _mp4Start;
  int? _mp4End;

  // Extracted MP4 + video controller.
  String? _extractedMp4Path;
  VideoPlayerController? _video;
  bool _isPlaying = false;
  // True while the current playback is a looping (long-press) session.
  bool _isLoopingPlay = false;
  bool _extractInFlight = false;
  bool _decodeFailed = false;
  bool _disposed = false;


  // Auto-play guard — fires exactly once after parser resolves motion-photo.
  bool _autoPlayTriggered = false;
  // Playback has reached natural end at least once → video layer can fade
  // out + play button becomes the canonical "replay" affordance.
  bool _autoPlayFinished = false;

  // UX overlays.
  bool _longPressedWithoutVideo = false;
  Timer? _noVideoHideTimer;

  // Listener hook installed on _video — kept as a field so we can remove
  // it from the controller in dispose and in re-init paths.
  VoidCallback? _videoListener;

  @override
  void initState() {
    super.initState();
    _taskId = 'preview-${DateTime.now().microsecondsSinceEpoch}';
    // Reject files larger than the fix_service ceiling up-front. This is
    // generous (2 GiB) — most photos are <30 MB — but prevents us from
    // starting a multi-hundred-MB sandbox copy for a pathological input.
    if (widget.args.sizeBytes > LivebackConstants.maxFileSizeBytes) {
      _oversized = true;
    } else {
      unawaited(_resolveSandboxThenProbe());
    }
  }

  Future<void> _resolveSandboxThenProbe() async {
    try {
      final path = await _channel.copyInputToSandbox(
        contentUri: widget.args.contentUri,
        taskId: _taskId,
      );
      if (!mounted) return;
      setState(() {
        _sandboxPath = path;
        _sandboxReady = true;
        _probing = true;
      });

      final structure = await _parser.parse(path);
      if (!mounted) return;
      final start = structure.mp4Start;
      final end = structure.mp4End;
      setState(() {
        _mp4Start = start;
        _mp4End = end;
        _isMotionPhoto = start != null && end != null && end > start;
        _probing = false;
      });

      // Kick off the single auto-play if we haven't already. Long-press can
      // race this — if a looping session is already in flight, skip.
      if (_isMotionPhoto && !_autoPlayTriggered && !_extractInFlight) {
        _autoPlayTriggered = true;
        unawaited(_extractAndPlay(looping: false));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _sandboxReady = true;
        _probing = false;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _noVideoHideTimer?.cancel();
    final controller = _video;
    _video = null;
    final listener = _videoListener;
    _videoListener = null;
    if (listener != null && controller != null) {
      controller.removeListener(listener);
    }
    unawaited(() async {
      await controller?.dispose();
    }());
    final extracted = _extractedMp4Path;
    if (extracted != null) {
      unawaited(() async {
        try {
          final f = File(extracted);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }());
    }
    // Fire-and-forget sandbox cleanup — best-effort per MediaStoreChannel
    // contract.
    unawaited(_channel.releaseSandbox(taskId: _taskId).catchError((_) {}));
    super.dispose();
  }

  Future<void> _handleLongPressStart(LongPressStartDetails _) async {
    if (!_sandboxReady || _loadError != null || _oversized) return;

    if (!_isMotionPhoto) {
      _noVideoHideTimer?.cancel();
      setState(() => _longPressedWithoutVideo = true);
      _noVideoHideTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _longPressedWithoutVideo = false);
      });
      return;
    }
    await _extractAndPlay(looping: true);
  }

  Future<void> _handleLongPressEnd(LongPressEndDetails _) async {
    _noVideoHideTimer?.cancel();
    if (_longPressedWithoutVideo) {
      setState(() => _longPressedWithoutVideo = false);
    }
    final v = _video;
    if (v != null && v.value.isInitialized && _isLoopingPlay) {
      await v.pause();
      await v.seekTo(Duration.zero);
      v.setLooping(false);
    }
    if (mounted && _isPlaying && _isLoopingPlay) {
      setState(() {
        _isPlaying = false;
        _isLoopingPlay = false;
        // A long-press that runs to completion without an explicit stop is
        // still counted as a play — expose the play button afterward.
        _autoPlayFinished = true;
      });
    }
  }

  /// Tapping the round play button — replay once, non-looping.
  Future<void> _handlePlayButtonTap() async {
    if (!_isMotionPhoto || !_sandboxReady || _loadError != null) return;
    await _extractAndPlay(looping: false);
  }

  /// Installs (or replaces) the listener that watches playback progress
  /// and flips the video layer off when playback reaches natural end.
  /// The 100 ms epsilon matches the brief's allowed slack for codecs that
  /// don't tick exactly to `duration`.
  void _installEndOfPlaybackListener(VideoPlayerController c) {
    // Remove stale listener if any (re-init path).
    final stale = _videoListener;
    if (stale != null) {
      c.removeListener(stale);
    }
    void listener() {
      if (!mounted || _disposed) return;
      if (_video != c) return; // a later init replaced this controller
      final v = c.value;
      if (!v.isInitialized) return;
      // Only non-looping sessions get the fade-out. Looping long-press
      // naturally never hits this condition.
      if (_isLoopingPlay) return;
      final dur = v.duration;
      if (dur <= Duration.zero) return;
      const epsilon = Duration(milliseconds: 100);
      final reachedEnd = v.position + epsilon >= dur;
      final stoppedAfterStart =
          !v.isPlaying && v.position > Duration.zero && _isPlaying;
      if (reachedEnd || stoppedAfterStart) {
        setState(() {
          _isPlaying = false;
          _autoPlayFinished = true;
        });
      }
    }

    _videoListener = listener;
    c.addListener(listener);
  }

  Future<void> _extractAndPlay({required bool looping}) async {
    if (_extractInFlight) return;
    final src = _sandboxPath;
    final start = _mp4Start;
    final end = _mp4End;
    if (src == null || start == null || end == null) return;

    // Controller already ready → seek + play, honouring the requested
    // looping flag. Lets long-press take over an initialized auto-play
    // controller without tearing it down.
    if (_video != null && _video!.value.isInitialized) {
      final v = _video!;
      v.setLooping(looping);
      await v.seekTo(Duration.zero);
      await v.play();
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _isLoopingPlay = looping;
      });
      return;
    }

    _extractInFlight = true;
    try {
      // Extract MP4 into cache/liveback-io/preview-<id>.mp4.
      final sandboxDir = File(src).parent.path;
      final mp4Path = '$sandboxDir/$_taskId.mp4';

      if (_extractedMp4Path == null) {
        await extractMp4Range(
          srcPath: src,
          mp4Start: start,
          mp4End: end,
          dstPath: mp4Path,
        );
        if (_disposed) {
          // User backed out during extract — delete the half-written temp
          // file so the sandbox sweep has less to reclaim.
          unawaited(() async {
            try {
              final f = File(mp4Path);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }());
          return;
        }
        _extractedMp4Path = mp4Path;
      }

      final controller = VideoPlayerController.file(File(mp4Path));
      try {
        await controller.initialize();
      } catch (e) {
        await controller.dispose();
        if (!mounted) return;
        setState(() {
          _decodeFailed = true;
        });
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _decodeFailed = false);
        });
        return;
      }
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      controller.setLooping(looping);
      _installEndOfPlaybackListener(controller);
      await controller.play();
      setState(() {
        _video = controller;
        _isPlaying = true;
        _isLoopingPlay = looping;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _decodeFailed = true;
      });
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _decodeFailed = false);
      });
    } finally {
      _extractInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Force the dark palette for preview chrome (back chip, overlays) —
    // scaffold bg stays the brand splash charcoal regardless of system theme.
    const bgColor = Color(0xFF0B1013);
    const darkColors = LivebackColors.dark;

    // Play button is shown once we know it's a Motion Photo AND either
    // the initial auto-play finished, or we're in a non-playing steady
    // state (e.g. user tapped back from long-press) so they can replay.
    // Gated by isInitialized so we never show "play" before there's
    // anything to play.
    final showPlayButton = _isMotionPhoto &&
        !_isPlaying &&
        !_decodeFailed &&
        _loadError == null &&
        (_autoPlayFinished || _video != null);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Center photo / video layer.
          Center(child: _buildContent(darkColors)),

          // Hit-absorbing overlay for long-press. Sits above the photo so
          // long-press is recognised anywhere on the screen. The outer
          // GestureDetector uses HitTestBehavior.opaque so empty letterbox
          // area also triggers.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: _handleLongPressEnd,
            ),
          ),

          // Top-left back chip.
          Positioned(
            left: 8,
            top: MediaQuery.paddingOf(context).top + 4,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back_ios_new,
                    color: darkColors.ink, size: 20),
                splashRadius: 22,
              ),
            ),
          ),

          // Round play button at bottom center (replaces the old hint pill).
          if (showPlayButton)
            _PlayButton(onTap: _handlePlayButtonTap, colors: darkColors),

          // 无视频段 overlay pill.
          if (_longPressedWithoutVideo)
            _CenterPill(
              text: context.l10n.previewNoVideo,
              colors: darkColors,
            ),

          // Decode failure overlay.
          if (_decodeFailed)
            _CenterPill(
              text: context.l10n.previewDecodeFailed,
              colors: darkColors,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(LivebackColors colors) {
    if (_oversized) {
      return _MessageBanner(
        message: context.l10n.previewTooLarge,
        colors: colors,
      );
    }
    if (_loadError != null) {
      return _MessageBanner(
        message: context.l10n.previewLoadFailed,
        colors: colors,
      );
    }
    if (!_sandboxReady || _probing) {
      return SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.inkFaint,
        ),
      );
    }
    final path = _sandboxPath;
    if (path == null) {
      return _MessageBanner(
        message: context.l10n.previewLoadFailed,
        colors: colors,
      );
    }

    // Layered: still image always present (behind video). Video layer
    // fades in/out on top when playing.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        InteractiveViewer(
          panEnabled: true,
          scaleEnabled: true,
          minScale: 1,
          maxScale: 4,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        if (_video != null && _video!.value.isInitialized)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _isPlaying ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Round play button that replaces the old "长按预览视频" hint pill.
/// 52×52 cream circle with slate play triangle — matches the dark-palette
/// chrome used elsewhere on PreviewPage.
class _PlayButton extends StatelessWidget {
  final VoidCallback onTap;
  final LivebackColors colors;
  const _PlayButton({required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + 24,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Cream fill per brand dark-chrome palette.
                color: const Color(0xFFF4EEE2),
                border: Border.all(color: colors.border, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              // Slightly inset arrow so its visual centre matches circle
              // centre (the right-pointing triangle's optical weight skews
              // left without the 2-dp nudge).
              child: const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Icon(
                  Icons.play_arrow,
                  color: Color(0xFF0B1013),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterPill extends StatelessWidget {
  final String text;
  final LivebackColors colors;
  const _CenterPill({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.borderStrong, width: 1),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: colors.ink,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String message;
  final LivebackColors colors;
  const _MessageBanner({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 36, color: colors.inkFaint),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colors.inkDim,
            ),
          ),
        ],
      ),
    );
  }
}
