// Owner: T3 (UI teammate). Reference: preview_page.dart § extract helper.
//
// Pure-Dart MP4 byte-range extractor. Lives in its own file so the CLI
// smoke tool (`tool/extract_mp4_smoke.dart`) can import it without
// pulling Flutter or video_player symbols through `preview_page.dart`.
//
// Streams `[mp4End - mp4Start]` bytes from [srcPath]'s `[mp4Start, mp4End)`
// range into [dstPath] through a 256 KB rolling buffer. Returns the number
// of bytes written. Throws:
//   - [ArgumentError] if mp4End <= mp4Start
//   - [StateError]    on unexpected EOF before the requested span is read

import 'dart:io';
import 'dart:typed_data';

/// Size of the rolling copy buffer. Chosen to balance per-syscall overhead
/// against peak RSS: 256 KB ≪ 2 MB motion-photo parser cap, and 4× the
/// JPEG-entropy scanner's 64 KB (both in motion_photo_parser.dart).
const int kExtractBufferSize = 256 * 1024;

Future<int> extractMp4Range({
  required String srcPath,
  required int mp4Start,
  required int mp4End,
  required String dstPath,
}) async {
  if (mp4End <= mp4Start) {
    throw ArgumentError('mp4End ($mp4End) must be > mp4Start ($mp4Start)');
  }
  final total = mp4End - mp4Start;
  final src = await File(srcPath).open();
  RandomAccessFile? dst;
  try {
    dst = await File(dstPath).open(mode: FileMode.write);
    await src.setPosition(mp4Start);
    var remaining = total;
    final buffer = Uint8List(kExtractBufferSize);
    while (remaining > 0) {
      final want = remaining < kExtractBufferSize ? remaining : kExtractBufferSize;
      final read = await src.readInto(buffer, 0, want);
      if (read <= 0) {
        throw StateError('unexpected EOF at offset ${total - remaining}');
      }
      await dst.writeFrom(buffer, 0, read);
      remaining -= read;
    }
    return total;
  } finally {
    await src.close();
    if (dst != null) {
      await dst.close();
    }
  }
}
