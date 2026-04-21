// Owner: T1 (binary-format teammate).
// Reference: Doc 1 §A.1 (SSoT — authoritative) + Doc 2 §6.
// DO NOT edit signatures without an architecture amendment to both docs.
//
// This is the single most important stub in the bootstrap: the Worker
// isolate (T3 owns worker plumbing) dispatches every task through this
// signature. Input/output are ALWAYS filesystem paths inside the Plan A
// copy-through sandbox (cache/liveback-io/). Content URIs never reach
// this layer.

import 'dart:io';
import 'dart:typed_data';

import '../core/cancellation.dart';
import '../core/constants.dart';
import '../core/task_phase.dart';
import '../exceptions/liveback_exceptions.dart';
import '../models/fix_result.dart';
import '../models/motion_photo_structure.dart';
import '_sef_constants.dart';
import 'exif_rewriter.dart';
import 'motion_photo_parser.dart';
import 'sef_writer.dart';

class FixService {
  static const int _copyChunkBytes = 64 * 1024;

  /// Single-file orchestration. Runs inside the Worker Isolate.
  ///
  /// Both [inputPath] and [outputPath] are filesystem paths inside the
  /// app's sandbox (populated by `MediaStoreChannel.copyInputToSandbox`
  /// before dispatch). The fix_service never sees content:// URIs.
  ///
  /// Progress: emits [TaskPhase] values via [onPhase] as the pipeline
  /// advances across parse / inject / write boundaries.
  ///
  /// Cancellation: [cancel] is polled at step boundaries (see Doc 2 §6.5).
  ///   Throws [OperationCancelledException] if cancel fires mid-process.
  ///
  /// Errors: throws a `LivebackException` subclass whose `.errorCode` is
  /// one of the `ErrorCodes.*` constants in `core/error_codes.dart`.
  Future<FixResult> fix({
    required String inputPath,
    required String outputPath,
    required CancellationToken cancel,
    void Function(TaskPhase phase)? onPhase,
    FixOptions options = const FixOptions(),
  }) async {
    final t0 = DateTime.now().millisecondsSinceEpoch;

    final inputFile = File(inputPath);
    final stat = inputFile.statSync();
    final originalSize = stat.size;
    final originalMtimeMs = stat.modified.millisecondsSinceEpoch;

    if (originalSize > options.maxFileSizeBytes) {
      throw FileTooLargeException(size: originalSize);
    }

    cancel.throwIfCancelled('');

    onPhase?.call(TaskPhase.parsing);
    final structure = await MotionPhotoParser().parse(inputPath, cancel: cancel);

    // dateTakenMs fallback owned here (per review B7):
    final dateTakenMs = structure.exifAppOne?.dateTimeOriginalMs
        ?? DateTime.now().millisecondsSinceEpoch;

    // Skipped paths: return FixResult(kind: skipped*) — NO output file,
    // NO throw. UI maps them to "已是三星格式,无需修复" / "不是实况图,
    // 已跳过" per brand §5.2.
    if (structure.mp4Start == null) {
      return FixResult(
        kind: FixResultKind.skippedNotMotionPhoto,
        elapsedMs: DateTime.now().millisecondsSinceEpoch - t0,
        originalSizeBytes: originalSize,
        outputSizeBytes: originalSize,
        videoDurationSeconds: null,
        videoTooLongWarning: false,
        dateTakenMs: dateTakenMs,
        originalMtimeMs: originalMtimeMs,
      );
    }

    if (_isAlreadySamsungFormat(structure)) {
      return FixResult(
        kind: FixResultKind.skippedAlreadySamsung,
        elapsedMs: DateTime.now().millisecondsSinceEpoch - t0,
        originalSizeBytes: originalSize,
        outputSizeBytes: originalSize,
        videoDurationSeconds: structure.videoDurationSeconds,
        videoTooLongWarning: false,
        dateTakenMs: dateTakenMs,
        originalMtimeMs: originalMtimeMs,
      );
    }

    cancel.throwIfCancelled('');

    onPhase?.call(TaskPhase.injectingSef);

    final mp4Length = structure.mp4End! - structure.mp4Start!;
    final newExifBytes = _buildRewrittenExif(structure, inputPath);
    final inlineMarker = SefWriter.buildInlineMarker();
    // offsetFromSefhToInlineMarker = 24 + mp4Length, always.
    //   Both SEFH and the inline marker shift by the same EXIF delta, so
    //   the relative distance is invariant under EXIF rewrites.
    final sefTrailer = SefWriter.buildSefTrailer(
      offsetFromSefhToInlineMarker: kInlineMarkerTotalBytes + mp4Length,
    );

    cancel.throwIfCancelled('');
    onPhase?.call(TaskPhase.writing);

    final tmpPath = '$outputPath.tmp';
    try {
      await _streamWriteOutput(
        inputPath: inputPath,
        tmpPath: tmpPath,
        structure: structure,
        newExifBytes: newExifBytes,
        inlineMarker: inlineMarker,
        sefTrailer: sefTrailer,
        cancel: cancel,
      );
    } on OperationCancelledException {
      _tryDeleteFile(tmpPath);
      rethrow;
    } on LivebackException {
      _tryDeleteFile(tmpPath);
      rethrow;
    } on FileSystemException catch (e) {
      _tryDeleteFile(tmpPath);
      throw SefWriteFailedException(e);
    } catch (e) {
      _tryDeleteFile(tmpPath);
      throw SefWriteFailedException(e);
    }

    cancel.throwIfCancelled('');

    // Atomic rename + mtime preservation.
    try {
      File(tmpPath).renameSync(outputPath);
    } on FileSystemException catch (e) {
      _tryDeleteFile(tmpPath);
      throw WriteCorruptException(e);
    }

    try {
      File(outputPath).setLastModifiedSync(inputFile.lastModifiedSync());
    } catch (_) {
      // mtime preservation is best-effort; do not fail the whole pipeline.
    }

    final newSize = File(outputPath).statSync().size;
    final videoDur = structure.videoDurationSeconds;
    return FixResult(
      kind: FixResultKind.completed,
      elapsedMs: DateTime.now().millisecondsSinceEpoch - t0,
      originalSizeBytes: originalSize,
      outputSizeBytes: newSize,
      videoDurationSeconds: videoDur,
      videoTooLongWarning:
          videoDur != null && videoDur > options.videoWarnThresholdSeconds,
      dateTakenMs: dateTakenMs,
      originalMtimeMs: originalMtimeMs,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────────────

  /// Determines whether the source is already Samsung-shaped, per Doc 2
  /// §8.1 four-part rule.
  bool _isAlreadySamsungFormat(MotionPhotoStructure s) {
    final make = s.exifAppOne?.make?.trim().replaceAll('\u0000', '').toLowerCase();
    if (make != LivebackConstants.fakedExifMake.toLowerCase()) return false;
    final trailer = s.existingSefTrailer;
    if (trailer == null) return false;
    final hasMp = trailer.records.any((r) => r.typeCode == kMotionPhotoDataTypeCode);
    if (!hasMp) return false;
    return true;
  }

  /// Produces the new APP1 EXIF bytes along with the source-byte range
  /// they replace. Handles the three source shapes:
  ///
  ///  1. Source has EXIF with matching-length Make/Model → fast-path
  ///     in-place overwrite. Segment length unchanged.
  ///  2. Source has EXIF without Make/Model → slow-path full IFD0
  ///     rebuild. Segment length may grow.
  ///  3. Source has no EXIF APP1 at all (djimimo stripped case) →
  ///     buildFreshExifAppOne. Insertion point is at offset 2 (right
  ///     after SOI); `originalSegmentLength = 0`.
  _ExifPlan _buildRewrittenExif(MotionPhotoStructure s, String inputPath) {
    final rw = ExifRewriter();
    if (s.exifAppOne != null) {
      final srcBytes = _readExifRange(inputPath, s.exifAppOne!);
      final rebuilt = rw.rewriteMakeModel(
        originalAppOne: srcBytes,
        make: LivebackConstants.fakedExifMake,
        model: LivebackConstants.fakedExifModel,
      ).single;
      return _ExifPlan(
        segmentStart: s.exifAppOne!.segmentStart,
        originalSegmentLength: s.exifAppOne!.segmentLength,
        newSegmentBytes: rebuilt,
      );
    } else {
      // No EXIF at all — synthesize a fresh APP1 and insert right after SOI.
      final fresh = rw.buildFreshExifAppOne(
        make: LivebackConstants.fakedExifMake,
        model: LivebackConstants.fakedExifModel,
        imageWidth: 0, // unknown; djimimo sources don't expose pixel size
        imageHeight: 0,
        orientation: 1,
      ).single;
      return _ExifPlan(
        segmentStart: 2, // right after SOI
        originalSegmentLength: 0,
        newSegmentBytes: fresh,
      );
    }
  }

  /// Synchronous read of an EXIF APP1 segment from disk. APP1 is capped
  /// at 64 KB so a sync read is well within our memory budget (Doc 2 §9).
  Uint8List _readExifRange(String path, ExifBlock block) {
    final raf = File(path).openSync();
    try {
      raf.setPositionSync(block.segmentStart);
      final bytes = raf.readSync(block.segmentLength);
      // raf.readSync already returns a Uint8List; copy to break the view.
      return Uint8List.fromList(bytes);
    } finally {
      raf.closeSync();
    }
  }

  Future<void> _streamWriteOutput({
    required String inputPath,
    required String tmpPath,
    required MotionPhotoStructure structure,
    required _ExifPlan newExifBytes,
    required Uint8List inlineMarker,
    required Uint8List sefTrailer,
    required CancellationToken cancel,
  }) async {
    final src = await File(inputPath).open();
    final dst = await File(tmpPath).open(mode: FileMode.write);

    try {
      // Phase A: copy bytes from start to the EXIF segment start.
      if (newExifBytes.segmentStart > 0) {
        await _copyRange(src, dst, 0, newExifBytes.segmentStart, cancel);
      }

      // Phase B: emit the rewritten EXIF APP1 bytes.
      await dst.writeFrom(newExifBytes.newSegmentBytes);
      cancel.throwIfCancelled('');

      // Phase C: copy from (segmentStart + originalLen) to jpegEnd.
      final afterOldExif = newExifBytes.segmentStart + newExifBytes.originalSegmentLength;
      if (structure.jpegEnd > afterOldExif) {
        await _copyRange(src, dst, afterOldExif, structure.jpegEnd, cancel);
      }

      // Phase D: inline marker (24 B).
      await dst.writeFrom(inlineMarker);
      cancel.throwIfCancelled('');

      // Phase E: copy MP4 range verbatim.
      final mp4Start = structure.mp4Start;
      final mp4End = structure.mp4End;
      if (mp4Start == null || mp4End == null) {
        throw StateError('fix_service reached write phase without MP4 range');
      }
      await _copyRange(src, dst, mp4Start, mp4End, cancel);

      // Phase F: SEF trailer (32 B).
      await dst.writeFrom(sefTrailer);

      await dst.flush();
    } finally {
      await dst.close();
      await src.close();
    }
  }

  Future<void> _copyRange(
    RandomAccessFile src,
    RandomAccessFile dst,
    int start,
    int end,
    CancellationToken cancel,
  ) async {
    if (end <= start) return;
    await src.setPosition(start);
    var remaining = end - start;
    while (remaining > 0) {
      cancel.throwIfCancelled('');
      final n = remaining < _copyChunkBytes ? remaining : _copyChunkBytes;
      final chunk = await src.read(n);
      if (chunk.length != n) {
        throw SefWriteFailedException('short read $start..$end');
      }
      await dst.writeFrom(chunk);
      remaining -= n;
    }
  }

  void _tryDeleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Best effort — ignore.
    }
  }
}

class _ExifPlan {
  final int segmentStart;
  final int originalSegmentLength;
  final Uint8List newSegmentBytes;

  _ExifPlan({
    required this.segmentStart,
    required this.originalSegmentLength,
    required this.newSegmentBytes,
  });
}
