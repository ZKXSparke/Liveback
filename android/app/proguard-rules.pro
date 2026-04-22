# Flutter framework — preserves all engine classes accessed reflectively.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Our own Kotlin MethodChannel plugins (MediaStorePlugin, WeChatSharePlugin).
# Flutter's generated plugin registrant finds them by name at runtime.
-keep class com.sparker.liveback.** { *; }

# Kotlin coroutines continuation machinery — some reflection-based paths
# on older Android versions.
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}

# flutter_local_notifications — documented proguard requirements.
-keep class com.dexterous.** { *; }

# video_player (ExoPlayer under the hood).
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Keep source file names + line numbers for cleaner crash traces.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
