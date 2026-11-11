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

    // The test key that signs CI builds, so each one installs over the last.
    // It is not in the repository: CI writes it from the BEAZA_KEYSTORE_B64
    // secret and reads the password from BEAZA_KEYSTORE_PASSWORD. Without
    // them the build uses the debug key. Never use it for a store release.
    val testKey = file("../keystore/beaza-test.jks")
    val testKeyPassword = System.getenv("BEAZA_KEYSTORE_PASSWORD")
    val hasTestKey = testKey.exists() && !testKeyPassword.isNullOrEmpty()
    signingConfigs {
        if (hasTestKey) {
            create("beazaTest") {
                storeFile = testKey
                storePassword = testKeyPassword
                keyAlias = "beaza"
                keyPassword = testKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasTestKey) signingConfigs.getByName("beazaTest") else signingConfigs.getByName("debug")
            // R8 renamed ML Kit's internal classes and broke the receipt
            // reader on a real phone (NullPointerException inside ML Kit).
            // The app is small, so it is not shrunk or renamed.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// The release is built for 64-bit ARM only (every phone the project
// supports), but ML Kit's text reader shipped its x86_64 and 32-bit
// libraries too: about 18 MB nobody could use. Debug builds keep them for
// emulators.
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(
            listOf("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**"),
        )
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
