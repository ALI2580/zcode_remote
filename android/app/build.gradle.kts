plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Local builds read android/key.properties (git-ignored);
// CI provides the same values via GitHub Secrets as env vars so every
// published APK shares ONE signature and can overwrite-install.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

fun propOrEnv(name: String): String? =
    keystoreProperties.getProperty(name) ?: System.getenv("ANDROID_${name.uppercase()}")

android {
    namespace = "com.zcoderemote.zcode_remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.zcoderemote.zcode_remote"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFileProp = propOrEnv("storeFile")
            if (!storeFileProp.isNullOrBlank()) {
                keyAlias = propOrEnv("keyAlias")
                keyPassword = propOrEnv("keyPassword")
                storeFile = file(storeFileProp)
                storePassword = propOrEnv("storePassword")
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null && releaseSigning.storeFile != null) {
                signingConfig = releaseSigning
            } else {
                // Fall back to debug keys so `flutter build apk` still works
                // when no keystore is configured.
                signingConfig = signingConfigs.getByName("debug")
            }
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
