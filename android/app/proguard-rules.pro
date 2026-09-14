# Keep Flutter internal utility classes accessed via JNI by path_provider_android
-keep class io.flutter.util.** { *; }

# Keep AudioService and JustAudio classes for background media playback
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# Keep Gson / Hive serialization models
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep ExoPlayer / Media3 extractors, decoders and data sources
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Ignore warnings for clean R8 code compilation
-dontwarn **
