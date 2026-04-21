// Owner: T1 (binary-format teammate). Reference: Doc 2 §1.1 (last block).
// DO NOT edit signatures without an architecture amendment.
//
// Shared byte-manipulation helpers. Top-level functions (no class) so
// every module can import them with a single namespaced alias.

import 'dart:typed_data';

/// Reads a little-endian uint32 starting at [offset].
int readUint32Le(Uint8List src, int offset) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Reads a big-endian uint32 starting at [offset].
int readUint32Be(Uint8List src, int offset) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Reads a big-endian uint16 starting at [offset].
int readUint16Be(Uint8List src, int offset) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Writes a little-endian uint32 into [dst] at [offset].
void writeUint32Le(ByteData dst, int offset, int value) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Concatenates multiple byte lists into a single fresh [Uint8List].
Uint8List concatBytes(List<Uint8List> parts) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Byte-wise compares [length] bytes from `a[aOff]` vs `b[bOff]`.
bool bytesEqual(Uint8List a, int aOff, Uint8List b, int bOff, int length) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}

/// Substring-search over a byte range. [end] == -1 means "up to
/// haystack.length". Returns the first match position, or -1 if not
/// found.
int findBytes(Uint8List haystack, Uint8List needle, {int start = 0, int end = -1}) {
  throw UnimplementedError('T1 — Doc 2 §1.1 (bytes helpers)');
}
