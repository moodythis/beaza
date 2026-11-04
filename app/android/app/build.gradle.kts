plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "bh.beaza.beaza"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "bh.beaza.beaza"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Google sign-in (Credential Manager) needs Android 6 or newer.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // TEST ONLY key, committed so every CI build installs over the last one.
    // See ../keystore/README.md. Never use it for a store release.
    signingConfigs {
        create("beazaTest") {
            storeFile = file("../keystore/beaza-test.jks")
            storePassword = "removed-from-repo"
            keyAlias = "beaza"
            keyPassword = "removed-from-repo"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("beazaTest")
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
    // Receipt text recognition on the phone (Latin script; the model ships
    // inside the app, so no download and no network is needed).
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // FileProvider: the camera writes the photo to a temporary file.
    implementation("androidx.core:core:1.13.1")
}
