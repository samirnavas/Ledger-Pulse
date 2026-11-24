import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigning = Properties()
val releaseSigningFile = rootProject.file("key.properties")
if (releaseSigningFile.isFile) {
    releaseSigningFile.inputStream().use { releaseSigning.load(it) }
}

android {
    namespace = "com.paypr.app"
    compileSdk = flutter.compileSdkVersion
    buildToolsVersion = "35.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        compose = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.paypr.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningFile.isFile) {
            create("production") {
                fun setting(name: String): String =
                    requireNotNull(releaseSigning.getProperty(name)?.takeIf { it.isNotBlank() }) {
                        "Missing $name in android/key.properties"
                    }
                storeFile = rootProject.file(setting("storeFile"))
                storePassword = setting("storePassword")
                keyAlias = setting("keyAlias")
                keyPassword = setting("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A checkout without a private key can build an unsigned artifact.
            signingConfig = signingConfigs.findByName("production")
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
    implementation("androidx.compose.material3:material3:1.3.1")
}

flutter {
    source = "../.."
}

