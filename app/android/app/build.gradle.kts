import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.mightyflub.chipdeck"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.mightyflub.chipdeck"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The shared native core (libchipdeck.so): same CMake project and
        // sources as the Windows chipdeck.dll. Only the library is built.
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DCHIPDECK_BUILD_CLI=OFF",
                    "-DCHIPDECK_BUILD_TESTS=OFF",
                    "-DANDROID_STL=c++_static",
                )
                targets += "chipdeck-shared"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../../CMakeLists.txt")
        }
    }

    // Release signing. Android only installs an update over an existing
    // install when both APKs are signed with the same key. With
    // android/key.properties (never committed; CI writes it from repository
    // secrets, see docs/HANDOVER.md) releases use that key; without it they
    // fall back to the debug key, which differs between machines and CI runs.
    val keyProps = rootProject.file("key.properties")
    signingConfigs {
        if (keyProps.exists()) {
            create("release") {
                val props = Properties()
                keyProps.inputStream().use { props.load(it) }
                storeFile = rootProject.file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keyProps.exists()) "release" else "debug")
        }
    }
}

dependencies {
    // Media notification, lock screen and headset controls (PlaybackService.kt).
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.media:media:1.7.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
