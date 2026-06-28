import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing (Nekoko LLC). Credentials live in android/key.properties
// (git-ignored). When absent, release falls back to debug signing so CI and
// fresh clones still build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val sentryDsn = providers.environmentVariable("SENTRY_DSN").orNull.orEmpty()
val sentryEnvironment = providers.environmentVariable("SENTRY_ENVIRONMENT").orNull ?: "production"

android {
    namespace = "ad.neko.mithka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "ad.neko.mithka"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // TDLib (tdjson) needs API 21+. jniLibs/<abi>/libtdjson.so is bundled
        // automatically by the Android Gradle plugin (see scripts/build-tdjson-android.sh).
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["sentryDsn"] = sentryDsn
        manifestPlaceholders["sentryEnvironment"] = sentryEnvironment
    }

    packaging {
        jniLibs {
            // The APK is distributed directly from CI. Store native libraries
            // compressed so the arm64 APK is small enough for Telegram upload;
            // Android will extract them at install time.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the Nekoko LLC release key when android/key.properties
            // is present; otherwise debug-signed so CI / fresh clones still build.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ntgcalls (and other native plugins) resolve their Java classes by name
            // from native code via JNI (GetStaticMethodID); R8 obfuscation renames
            // those classes → JniAbort/SIGABRT at runtime in release (debug doesn't
            // minify, so it ran fine). The Java/Kotlin surface here is tiny — the APK
            // is almost entirely native .so + Dart AOT, which R8 can't shrink — so
            // disabling minification costs ~nothing and avoids release-only JNI crashes.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // ntgcalls — a from-scratch C++ Telegram-calls engine (WebRTC + opus + libvpx
    // statically bundled inside a self-contained libntgcalls.so per ABI). This is
    // the real media transport behind the CallMediaEngine seam; CallMediaPlugin
    // drives its 1:1 P2P API from the TDLib callStateReady payload.
    implementation("io.github.pytgcalls:ntgcalls:2.2.5")
    implementation("com.google.mlkit:language-id:17.0.6")
    implementation("com.google.mlkit:translate:17.0.3")
}
