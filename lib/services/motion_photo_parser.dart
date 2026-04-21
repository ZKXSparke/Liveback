// Owner: T1 (binary-format teammate). Reference: Doc 2 §1.1 + §2.
// DO NOT edit signatures without an architecture amendment.

import '../core/cancellation.dart';
import '../models/motion_photo_structure.dart';

/// Streams a JPEG + optional trailing MP4 + optional SEF trailer from a
/// file path into a [MotionPhotoStructure] value object. Pure Dart — no
/// Flutter imports, runnable inside a worker isolate.
///
/// See Doc 2 §2 for the algorithm. Peak buffer ≤ 2 MB across all phases.
class MotionPhotoParser {
  /// Returns the structure of the image file at [path]. Throws
  /// `InvalidFileFormatException` for non-JPEG inputs. [cancel], if
  /// provided, is polled at phase boundaries.
  Future<MotionPhotoStructure> parse(
    String path, {
    CancellationToken? cancel,
  }) {
    throw UnimplementedError('T1 — Doc 2 §2 (motion_photo_parser)');
  }
}
