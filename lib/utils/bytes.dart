// Owner: T1 (binary-format teammate). Reference: Doc 2 §1.1 (last block).
// DO NOT edit signatures without an architecture amendment.
//
// Shared byte-manipulation helpers. Top-level functions (no class) so
// every module can import them with a single namespaced alias.

import 'dart:typed_data';

/// Reads a little-endian uint32 starting at [offset].
int readUint32Le(Uint8List src, int offset) {
  if (offset < 0 || offset + 4 > src.length) {
    throw RangeError('readUint32Le: offset $offset out of range (len=${src.length})');
  }
  return src[offset] |
      (src[offset + 1] << 8) |
      (src[offset + 2] << 16) |
      (src[offset + 3] << 24);
}

/// Reads a big-endian uint32 starting at [offset].
int readUint32Be(Uint8List src, int offset) {
  if (offset < 0 || offset + 4 > src.length) {
    throw RangeError('readUint32Be: offset $offset out of range (len=${src.length})');
  }
  return (src[offset] << 24) |
      (src[offset + 1] << 16) |
      (src[offset + 2] << 8) |
      src[offset + 3];
}

/// Reads a big-endian uint16 starting at [offset].
int readUint16Be(Uint8List src, int offset) {
  if (offset < 0 || offset + 2 > src.length) {
    throw RangeError('readUint16Be: offset $offset out of range (len=${src.length})');
  }
  return (src[offset] << 8) | src[offset + 1];
}

/// Writes a little-endian uint32 into [dst] at [offset].
void writeUint32Le(ByteData dst, int offset, int value) {
  dst.setUint32(offset, value, Endian.little);
}

/// Concatenates multiple byte lists into a single fresh [Uint8List].
Uint8List concatBytes(List<Uint8List> parts) {
  var total = 0;
  for (final p in parts) {
    total += p.length;
  }
  final out = Uint8List(total);
  var o = 0;
  for (final p in parts) {
    out.setRange(o, o + p.length, p);
    o += p.length;
  }
  return out;
}

/// Byte-wise compares [length] bytes from `a[aOff]` vs `b[bOff]`.
bool bytesEqual(Uint8List a, int aOff, Uint8List b, int bOff, int length) {
  if (aOff < 0 || bOff < 0 || length < 0) return false;
  if (aOff + length > a.length || bOff + length > b.length) return false;
  for (var i = 0; i < length; i++) {
    if (a[aOff + i] != b[bOff + i]) return false;
  }
  return true;
}

/// Substring-search over a byte range. [end] == -1 means "up to
/// haystack.length". Returns the first match position, or -1 if not
/// found.
int findBytes(Uint8List haystack, Uint8List needle, {int start = 0, int end = -1}) {
  final hayEnd = end == -1 ? haystack.length : end;
  if (needle.isEmpty) return start;
  if (start < 0 || hayEnd > haystack.length || hayEnd < start) return -1;
  final nLen = needle.length;
  final last = hayEnd - nLen;
  outer:
  for (var i = start; i <= last; i++) {
    for (var j = 0; j < nLen; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
