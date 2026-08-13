import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of version control.
//
// android/key.properties holds the keystore path and its passwords. It is
// git-ignored on purpose: committing it hands anyone who clones the repo the
// ability to publish updates as this app. See README for how to generate one.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.atomid.store"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent. Changing it after publishing creates a separate listing
        // that existing installs cannot update to, so it is fixed here before
        // the first release rather than left as the template default.
        applicationId = "com.atomid.store"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            // Falls back to the debug key so `flutter run --release` still
            // works on a machine with no keystore. A debug-signed build is
            // fine for testing and is rejected by Play, so the warning below
            // is what stops one being uploaded by mistake.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

if (!hasReleaseKeystore) {
    logger.warn(
        "\n" +
            "┌──────────────────────────────────────────────────────────────┐\n" +
            "│ WARNING: no android/key.properties — release builds are      │\n" +
            "│ signed with the DEBUG key.                                   │\n" +
            "│                                                              │\n" +
            "│ Fine for testing. The Play Store will reject this build, and │\n" +
            "│ an app published with a key you cannot reproduce can never   │\n" +
            "│ be updated. See README before your first release.            │\n" +
            "└──────────────────────────────────────────────────────────────┘\n"
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
