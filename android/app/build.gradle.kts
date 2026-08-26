plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.echo_locate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14033849"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.echo_locate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ARCore requires API 24+. Flutter's default floor is lower, so this
        // is pinned rather than inherited — see the arcore dependency below.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
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
    
}


flutter {
    source = "../.."
}

dependencies {
    // M0 spike: ARCore depth + pose over a platform channel.
    //
    // The manifest marks ARCore as OPTIONAL, not required, so the app still
    // installs and runs on devices Google has not certified — the Infinix
    // X657C used for sonar testing is one of them, and budget hardware is
    // common among this app's target users. Scanning is gated at runtime by
    // ArCoreDepthHandler's availability check; everything else (sonar,
    // browse, navigate) keeps working.
    implementation("com.google.ar:core:1.42.0")

    // `RegisteredRoute` is the route laid into ARCore's world, and it is pure
    // geometry — no Android classes, no ARCore types, nothing that needs a
    // device. It is also where the arrow's accuracy is decided, and it has
    // twice been wrong in ways that look identical on a phone to the AR not
    // working at all. Those are exactly the sums worth pinning on the desk.
    testImplementation("junit:junit:4.13.2")
}
