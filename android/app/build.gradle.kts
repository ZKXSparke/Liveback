plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sparker.liveback"
    // Explicit per v1.1 §2 / Doc 3 §11 (not tracking flutter.compileSdkVersion default).
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.sparker.liveback"
        minSdk = 29        // v1.1 §2: Android 10 minimum for scoped-storage MediaStore flow
        targetSdk = 34     // v1.1 §2: Android 14 target
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Single APK build target per user directive — do NOT enable ABI splits here.
    // Doc 3 §11 mentions splits but user policy overrides: one universal APK.
}

flutter {
    source = "../.."
}
