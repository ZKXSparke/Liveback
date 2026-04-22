import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — reads android/key.properties (gitignored). If the file is
// missing (e.g. CI without secrets, fresh checkout), the release build falls
// back to the debug key so `flutter build apk --release` still produces an
// APK, just not one you should distribute.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val hasReleaseKey = keystoreProperties.containsKey("storeFile")

android {
    namespace = "com.sparker.liveback"
    // compileSdk = 36: bumped from Doc 3 §11's 34 because plugin AAR metadata
    // (shared_preferences_android, integration_test on current pub releases)
    // requires compileSdk ≥ 36. Target/min stay on Doc 3's 34/29 baseline.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires core library desugaring
        // (java.time backport on minSdk 29).
        isCoreLibraryDesugaringEnabled = true
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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Single APK build target per user directive — do NOT enable ABI splits here.
    // Doc 3 §11 mentions splits but user policy overrides: one universal APK.
}

dependencies {
    // Coroutines — used by MediaStorePlugin / WeChatSharePlugin (Doc 3 §2 threading).
    // Explicit because Flutter's AGP bits do not guarantee it transitively.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // AndroidX core + annotations (Doc 3 §11).
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.annotation:annotation:1.8.0")
    // FlutterFragmentActivity lives in the Flutter embedding androidx artefact,
    // which Flutter's gradle plugin brings in automatically.

    // Core library desugaring — required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
