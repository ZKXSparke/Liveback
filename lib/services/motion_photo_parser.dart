// Owner: T1 (binary-format teammate). Reference: Doc 2 §1.1 + §2.
// DO NOT edit signatures without an architecture amendment.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/cancellation.dart';
import '../exceptions/liveback_exceptions.dart';
import '../models/motion_photo_structure.dart';
import '../utils/bytes.dart';
import '_sef_constants.dart';
import 'mp4_duration_probe.dart';

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
    String taskId = '',
  }) async {
    final file = File(path);
    final raf = await file.open();
    try {
      final fileSize = await raf.length();
      if (fileSize < 4) {
        throw InvalidFileFormatException('file < 4 bytes');
      }

      // Phase 1: SOI.
      await raf.setPosition(0);
      final first2 = await raf.read(2);
      if (first2.length < 2 || first2[0] != 0xFF || first2[1] != 0xD8) {
        throw InvalidFileFormatException('missing SOI (FF D8)');
      }

      // Phase 2: walk JPEG segments.
      final walk = await _walkJpegSegments(raf, fileSize, cancel, taskId);

      cancel?.throwIfCancelled(taskId);

      // Phase 3: detect optional inline marker then ftyp.
      final jpegEnd = walk.jpegEnd;
      var mp4Scan = jpegEnd;
      var hasInline = false;
      int? inlineOffset;
      if (jpegEnd + kInlineMarkerTotalBytes <= fileSize) {
        await raf.setPosition(jpegEnd);
        final peek = await raf.read(kInlineMarkerTotalBytes);
        if (peek.length == kInlineMarkerTotalBytes && _isInlineMarker(Uint8List.fromList(peek))) {
          hasInline = true;
          inlineOffset = jpegEnd;
          mp4Scan = jpegEnd + kInlineMarkerTotalBytes;
        }
      }

      final mp4Start = await _scanForFtyp(raf, mp4Scan, fileSize);

      // Phase 4: SEF trailer detection.
      final sefDetect = await _detectSefTrailer(raf, fileSize);
      final existingTrailer = sefDetect.trailer;
      final mp4End = existingTrailer != null ? sefDetect.mp4End : fileSize;

      // Phase 5: mvhd probe (null-tolerant).
      int? durationUnits;
      int? timescale;
      if (mp4Start != null && mp4End > mp4Start) {
        final d = await Mp4DurationProbe().probe(raf, mp4Start, mp4End);
        if (d != null) {
          durationUnits = d.durationUnits;
          timescale = d.timescale;
        }
      }

      return MotionPhotoStructure(
        fileSize: fileSize,
        jpegStart: 0,
        jpegEnd: jpegEnd,
        mp4Start: mp4Start,
        mp4End: mp4Start == null ? null : mp4End,
        hasExistingSefInlineMarker: hasInline,
        existingSefInlineMarkerOffset: inlineOffset,
        existingSefTrailer: existingTrailer,
        exifAppOne: walk.exifBlock,
        xmpSegmentOffset: walk.xmpOffset,
        xmpLength: walk.xmpLength,
        mvhdDurationUnits: durationUnits,
        mvhdTimescale: timescale,
      );
    } finally {
      await raf.close();
    }
  }

  Future<_JpegWalkResult> _walkJpegSegments(
    RandomAccessFile raf,
    int fileSize,
    CancellationToken? cancel,
    String taskId,
  ) async {
    var pos = 2;
    ExifBlock? exif;
    int? xmpOff;
    int? xmpLen;

    while (true) {
      cancel?.throwIfCancelled(taskId);
      if (pos + 2 > fileSize) {
        throw InvalidFileFormatException('truncated before next marker');
      }
      await raf.setPosition(pos);
      final head = await raf.read(2);
      if (head.length < 2) {
        throw InvalidFileFormatException('truncated reading marker');
      }
      if (head[0] != 0xFF) {
        throw InvalidFileFormatException('expected FF at pos $pos');
      }
      final marker = head[1];
      if (marker == 0xD9) {
        return _JpegWalkResult(jpegEnd: pos + 2, exifBlock: exif, xmpOffset: xmpOff, xmpLength: xmpLen);
      }
      // SOS = FF DA → scan entropy-coded data for real EOI.
      if (marker == 0xDA) {
        if (pos + 4 > fileSize) {
          throw InvalidFileFormatException('truncated at SOS length');
        }
        await raf.setPosition(pos + 2);
        final lenB = await raf.read(2);
        if (lenB.length < 2) {
          throw InvalidFileFormatException('truncated at SOS length');
        }
        final len = (lenB[0] << 8) | lenB[1];
        final afterSos = pos + 2 + len;
        final eoi = await _scanEntropyForEoi(raf, afterSos, fileSize);
        if (eoi < 0) {
          throw InvalidFileFormatException('missing EOI after SOS');
        }
        return _JpegWalkResult(jpegEnd: eoi + 2, exifBlock: exif, xmpOffset: xmpOff, xmpLength: xmpLen);
      }
      // Stand-alone markers (no length field): RSTn (D0..D7), TEM (01), and
      // 00 (a literal 0xFF 0x00 inside entropy data — shouldn't happen outside
      // SOS, but tolerate defensively).
      if (marker >= 0xD0 && marker <= 0xD7) {
        pos += 2;
        continue;
      }
      if (marker == 0x00 || marker == 0x01) {
        pos += 2;
        continue;
      }

      // Length-prefixed segment.
      if (pos + 4 > fileSize) {
        throw InvalidFileFormatException('truncated segment length');
      }
      await raf.setPosition(pos + 2);
      final lenBytes = await raf.read(2);
      if (lenBytes.length < 2) {
        throw InvalidFileFormatException('truncated segment length');
      }
      final segLen = (lenBytes[0] << 8) | lenBytes[1];
      if (segLen < 2) {
        throw InvalidFileFormatException('bad segment length $segLen at pos $pos');
      }
      final segEnd = pos + 2 + segLen;
      if (segEnd > fileSize) {
        throw InvalidFileFormatException('segment extends past EOF');
      }

      if (marker == 0xE1) {
        // APP1 → could be EXIF or XMP.
        final headLen = segLen - 2 < 30 ? segLen - 2 : 30;
        await raf.setPosition(pos + 4);
        final headBytes = await raf.read(headLen);
        if (headBytes.length == headLen) {
          final h = Uint8List.fromList(headBytes);
          if (_startsWith(h, _exifId)) {
            // Read the full segment payload (size bounded by 64 KB).
            await raf.setPosition(pos);
            final wholeAppOne = await raf.read(2 + segLen);
            final exifBytes = Uint8List.fromList(wholeAppOne);
            exif = _parseExifBlock(exifBytes, pos);
          } else if (_startsWith(h, _xmpId)) {
            xmpOff = pos;
            xmpLen = segLen;
          }
        }
      }

      pos = segEnd;
    }
  }

  /// Proper SOS entropy-data scanner that respects byte-stuffing
  /// (`FF 00` is an escaped 0xFF, `FF D0..D7` are restart markers).
  /// Returns the file position of the real EOI's `FF` byte, or -1.
  Future<int> _scanEntropyForEoi(RandomAccessFile raf, int start, int fileSize) async {
    const bufSize = 64 * 1024;
    var pos = start;
    while (pos < fileSize) {
      final remaining = fileSize - pos;
      final readLen = remaining < bufSize ? remaining : bufSize;
      await raf.setPosition(pos);
      final chunkList = await raf.read(readLen);
      final chunk = chunkList is Uint8List ? chunkList : Uint8List.fromList(chunkList);
      if (chunk.length < readLen) {
        return -1;
      }
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 0xFF) continue;
        // Peek next byte — if end of chunk, re-read via seek to see across
        // buffer boundary.
        int next;
        if (i + 1 < chunk.length) {
          next = chunk[i + 1];
        } else if (pos + i + 1 < fileSize) {
          await raf.setPosition(pos + i + 1);
          final peek = await raf.read(1);
          if (peek.isEmpty) return -1;
          next = peek[0];
        } else {
          return -1;
        }
        if (next == 0x00) {
          // Byte stuffing — skip the 0x00.
          continue;
        }
        if (next >= 0xD0 && next <= 0xD7) {
          // Restart marker — not an EOI.
          continue;
        }
        if (next == 0xFF) {
          // Fill byte 0xFF — the actual marker is later.
          continue;
        }
        if (next == 0xD9) {
          return pos + i;
        }
        // Any other marker inside entropy data → the scan has stepped out
        // of SOS. Treat the previous position as EOI boundary? Per spec
        // this shouldn't occur; treat as malformed.
        return -1;
      }
      pos += chunk.length;
    }
    return -1;
  }

  /// Scans [start..end) for the 4-byte `ftyp` magic. Looks in the
  /// immediate window after JPEG EOI (bounded by 64 bytes per Doc 2 §2.2).
  /// Returns the byte offset of the 4-byte `ftyp` within the box header
  /// (i.e., `ftypOffset = boxStart` since `ftyp` sits at size(4)+type(4),
  /// but the parser needs the BOX start — which is 4 bytes BEFORE the
  /// `ftyp` ASCII). See Doc 2 §2 "Phase 3: detect ftyp" and §2.2.
  ///
  /// IMPORTANT: returns the position of the box start (size field), NOT
  /// of the `ftyp` ASCII. The MP4 parser consumes [size][type] pairs.
  Future<int?> _scanForFtyp(RandomAccessFile raf, int start, int fileEnd) async {
    // Look within a 64-byte window past `start` for the `ftyp` ASCII
    // (i.e., the box TYPE field). The box START is 4 bytes earlier.
    final limit = (start + 64).clamp(start, fileEnd);
    final windowLen = limit - start;
    if (windowLen < 8) return null;
    await raf.setPosition(start);
    final win = await raf.read(windowLen);
    if (win.length < 8) return null;
    final buf = Uint8List.fromList(win);
    final idx = findBytes(buf, kFtypMagic);
    if (idx < 4) return null; // must have 4-byte size before
    // Sanity-check: the size field at idx-4 should be ≥ 8.
    final size = readUint32Be(buf, idx - 4);
    if (size < 8 || size > fileEnd) {
      return null;
    }
    return start + (idx - 4);
  }

  Future<_SefDetectResult> _detectSefTrailer(RandomAccessFile raf, int fileSize) async {
    if (fileSize < 32) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    await raf.setPosition(fileSize - 4);
    final tail = await raf.read(4);
    if (tail.length != 4) return _SefDetectResult(mp4End: fileSize, trailer: null);
    if (!_bytesEq(tail, kSeftMagic)) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    await raf.setPosition(fileSize - 8);
    final sefSizeBytes = await raf.read(4);
    if (sefSizeBytes.length != 4) return _SefDetectResult(mp4End: fileSize, trailer: null);
    final sefSize = readUint32Le(Uint8List.fromList(sefSizeBytes), 0);
    if (sefSize < 24 || sefSize > fileSize - 8) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    final sefhPos = fileSize - 8 - sefSize;
    if (sefhPos < 0) return _SefDetectResult(mp4End: fileSize, trailer: null);
    await raf.setPosition(sefhPos);
    final magic = await raf.read(4);
    if (magic.length != 4 || !_bytesEq(magic, kSefhMagic)) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    await raf.setPosition(sefhPos + 4);
    final verBytes = await raf.read(4);
    final countBytes = await raf.read(4);
    if (verBytes.length != 4 || countBytes.length != 4) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    final version = readUint32Le(Uint8List.fromList(verBytes), 0);
    final recordCount = readUint32Le(Uint8List.fromList(countBytes), 0);
    if (recordCount == 0 || recordCount > 32) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    // Each record is 12 bytes. Check we have room.
    final recEnd = sefhPos + 12 + recordCount * 12;
    if (recEnd > fileSize - 8) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    await raf.setPosition(sefhPos + 12);
    final recBytesList = await raf.read(recordCount * 12);
    if (recBytesList.length != recordCount * 12) {
      return _SefDetectResult(mp4End: fileSize, trailer: null);
    }
    final recBytes = Uint8List.fromList(recBytesList);
    final records = <SefRecord>[];
    for (var i = 0; i < recordCount; i++) {
      records.add(SefRecord(
        typeCode: readUint32Be(recBytes, i * 12),
        offsetFromSefh: readUint32Le(recBytes, i * 12 + 4),
        dataLength: readUint32Le(recBytes, i * 12 + 8),
      ));
    }
    return _SefDetectResult(
      mp4End: sefhPos,
      trailer: ExistingSefTrailer(
        sefhFilePosition: sefhPos,
        version: version,
        recordCount: recordCount,
        records: records,
        declaredSefSize: sefSize,
      ),
    );
  }

  /// Parses an APP1 EXIF segment for Make, Model, and DateTimeOriginal.
  /// Silent on parse errors inside the TIFF (returns partial/null values).
  /// Used read-only — no byte mutation.
  ExifBlock _parseExifBlock(Uint8List appOne, int segmentStart) {
    final segmentLength = appOne.length;
    String? make;
    String? model;
    int? dateTimeOriginalMs;

    // Safe to bail at any point on parse error.
    try {
      final tiff = Uint8List.view(
        appOne.buffer,
        appOne.offsetInBytes + 10,
        appOne.length - 10,
      );
      Endian endian;
      if (tiff.length < 8) {
        return ExifBlock(
          segmentStart: segmentStart,
          segmentLength: segmentLength,
          make: null,
          model: null,
          dateTimeOriginalMs: null,
        );
      }
      if (tiff[0] == 0x49 && tiff[1] == 0x49) {
        endian = Endian.little;
      } else if (tiff[0] == 0x4D && tiff[1] == 0x4D) {
        endian = Endian.big;
      } else {
        return ExifBlock(
          segmentStart: segmentStart,
          segmentLength: segmentLength,
          make: null,
          model: null,
          dateTimeOriginalMs: null,
        );
      }
      final ifd0Offset = _u32(tiff, 4, endian);
      if (ifd0Offset + 2 > tiff.length) {
        return ExifBlock(
          segmentStart: segmentStart,
          segmentLength: segmentLength,
          make: null,
          model: null,
          dateTimeOriginalMs: null,
        );
      }
      final count = _u16(tiff, ifd0Offset, endian);

      int? exifIfdOffset;
      for (var i = 0; i < count; i++) {
        final off = ifd0Offset + 2 + i * 12;
        if (off + 12 > tiff.length) break;
        final tag = _u16(tiff, off, endian);
        final type = _u16(tiff, off + 2, endian);
        final cnt = _u32(tiff, off + 4, endian);
        if (tag == 0x010F && type == 2) {
          make = _readAscii(tiff, off, cnt, endian);
        } else if (tag == 0x0110 && type == 2) {
          model = _readAscii(tiff, off, cnt, endian);
        } else if (tag == 0x8769 && type == 4) {
          exifIfdOffset = _u32(tiff, off + 8, endian);
        }
      }

      // Look for DateTimeOriginal (0x9003) inside ExifIFD.
      if (exifIfdOffset != null && exifIfdOffset + 2 <= tiff.length) {
        final eCount = _u16(tiff, exifIfdOffset, endian);
        for (var i = 0; i < eCount; i++) {
          final off = exifIfdOffset + 2 + i * 12;
          if (off + 12 > tiff.length) break;
          final tag = _u16(tiff, off, endian);
          final type = _u16(tiff, off + 2, endian);
          final cnt = _u32(tiff, off + 4, endian);
          if (tag == 0x9003 && type == 2) {
            final s = _readAscii(tiff, off, cnt, endian);
            dateTimeOriginalMs = _parseExifDateTime(s);
            break;
          }
        }
      }
    } catch (_) {
      // Swallow any parse error — Make/Model/date stay null.
    }

    return ExifBlock(
      segmentStart: segmentStart,
      segmentLength: segmentLength,
      make: make,
      model: model,
      dateTimeOriginalMs: dateTimeOriginalMs,
    );
  }

  String? _readAscii(Uint8List tiff, int entryOff, int count, Endian endian) {
    Uint8List bytes;
    if (count <= 4) {
      bytes = Uint8List.fromList(
        tiff.sublist(entryOff + 8, entryOff + 8 + count),
      );
    } else {
      final poolOff = _u32(tiff, entryOff + 8, endian);
      if (poolOff + count > tiff.length) return null;
      bytes = Uint8List.fromList(tiff.sublist(poolOff, poolOff + count));
    }
    // Strip the trailing null(s).
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end -= 1;
    }
    // Defensive: only decode if all printable ASCII.
    for (var i = 0; i < end; i++) {
      if (bytes[i] < 0x20 || bytes[i] > 0x7E) {
        // Non-printable → stop decoding here; take what we have.
        end = i;
        break;
      }
    }
    return String.fromCharCodes(bytes.sublist(0, end));
  }

  int? _parseExifDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    // EXIF DateTime format: "YYYY:MM:DD HH:MM:SS"
    // Accept variants that replace the two ':' in the date with '-'.
    final re = RegExp(r'^(\d{4})[:-](\d{2})[:-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})');
    final m = re.firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    final h = int.tryParse(m.group(4)!);
    final mi = int.tryParse(m.group(5)!);
    final se = int.tryParse(m.group(6)!);
    if ([y, mo, d, h, mi, se].any((x) => x == null)) return null;
    try {
      // EXIF DateTime is recorded in local time with no TZ. We treat as
      // UTC for determinism across devices (Doc 2 §6.2 accepts fallback
      // to DateTime.now() if null; the exact tz-interpretation is noted
      // as a Known limitation — callers only use this for DATE_TAKEN).
      final dt = DateTime.utc(y!, mo!, d!, h!, mi!, se!);
      return dt.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  int _u16(Uint8List buf, int off, Endian e) {
    if (e == Endian.little) {
      return buf[off] | (buf[off + 1] << 8);
    }
    return (buf[off] << 8) | buf[off + 1];
  }

  int _u32(Uint8List buf, int off, Endian e) {
    if (e == Endian.little) {
      return buf[off] |
          (buf[off + 1] << 8) |
          (buf[off + 2] << 16) |
          (buf[off + 3] << 24);
    }
    return (buf[off] << 24) |
        (buf[off + 1] << 16) |
        (buf[off + 2] << 8) |
        buf[off + 3];
  }

  bool _isInlineMarker(Uint8List peek) {
    if (peek.length < kInlineMarkerTotalBytes) return false;
    for (var i = 0; i < 4; i++) {
      if (peek[i] != kInlineMarkerMagic[i]) return false;
    }
    // name_length at offset 4 (LE uint32) must be 16.
    final nameLen = readUint32Le(peek, 4);
    if (nameLen != kInlineMarkerNameLength) return false;
    for (var i = 0; i < 16; i++) {
      if (peek[8 + i] != kMotionPhotoDataName[i]) return false;
    }
    return true;
  }

  bool _startsWith(Uint8List haystack, Uint8List needle) {
    if (haystack.length < needle.length) return false;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[i] != needle[i]) return false;
    }
    return true;
  }

  bool _bytesEq(List<int> a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static final _exifId = Uint8List.fromList([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
  static final _xmpId = Uint8List.fromList(
    'http://ns.adobe.com/xap/1.0/'.codeUnits,
  );
}

class _JpegWalkResult {
  final int jpegEnd;
  final ExifBlock? exifBlock;
  final int? xmpOffset;
  final int? xmpLength;
  _JpegWalkResult({required this.jpegEnd, this.exifBlock, this.xmpOffset, this.xmpLength});
}

class _SefDetectResult {
  final int mp4End;
  final ExistingSefTrailer? trailer;
  _SefDetectResult({required this.mp4End, this.trailer});
}
