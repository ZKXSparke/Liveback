// Owner: T2 (Android platform teammate). Reference: Doc 3 §2.1.
// DO NOT edit signatures without an architecture amendment.
//
// Pure value type — mirrors the Kotlin-side MediaItem JSON returned by
// MediaStoreChannel.queryImages (Doc 3 §2.1). Nullable projections
// (width/height/dateTakenMs) reflect MediaStore rows with missing columns.

class GalleryItem {
  /// Stable MediaStore `_ID`. Not typically displayed — used as dedupe key.
  final int id;

  /// `content://media/external/images/media/<id>` URI string.
  final String contentUri;

  /// DISPLAY_NAME column (e.g. `IMG_20260419_150334.jpg`).
  final String displayName;

  /// SIZE column, bytes.
  final int size;

  /// DATE_TAKEN → epoch ms. Null means the MediaStore row has no
  /// DATE_TAKEN; callers typically fall back to [dateAddedMs] for sort.
  final int? dateTakenMs;

  /// DATE_ADDED → epoch ms. Always present.
  final int dateAddedMs;

  /// WIDTH column; null if MediaStore never populated it.
  final int? width;

  /// HEIGHT column; null if MediaStore never populated it.
  final int? height;

  /// MIME_TYPE column; almost always `image/jpeg` for our filter.
  final String mimeType;

  const GalleryItem({
    required this.id,
    required this.contentUri,
    required this.displayName,
    required this.size,
    required this.dateTakenMs,
    required this.dateAddedMs,
    required this.width,
    required this.height,
    required this.mimeType,
  });
}
