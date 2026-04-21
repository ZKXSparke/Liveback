// Owner: T3 (UI teammate). Mirrors the Kotlin-side BucketAgg JSON returned
// by MediaStoreChannel.queryAlbums (MediaStorePlugin.kt).
//
// Pure value type. Nullable fields reflect MediaStore rows with missing
// columns (BUCKET_DISPLAY_NAME may be null for the DCIM root).

class GalleryAlbum {
  /// BUCKET_ID column — stable MediaStore album identifier (hash of the
  /// directory path). Use this as the primary key + in
  /// MediaStoreChannel.queryImages(bucketId: ...).
  final int bucketId;

  /// BUCKET_DISPLAY_NAME column — human-readable folder name. "(未命名)"
  /// when MediaStore returned NULL.
  final String displayName;

  /// content:// URI of the most-recent image in the bucket. Used as the
  /// cover thumbnail in the album picker bottom sheet.
  final String coverContentUri;

  /// Number of JPEG rows in this bucket the last time queryAlbums ran.
  final int count;

  const GalleryAlbum({
    required this.bucketId,
    required this.displayName,
    required this.coverContentUri,
    required this.count,
  });
}
