plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // ✅ Updated Kotlin plugin name
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ✅ Firebase plugin (must be last)
}

android {
    namespace = "com.example.baatchit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.baatchit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Firebase BoM (controls versions)
    implementation(platform("com.google.firebase:firebase-bom:34.11.0"))

    // ✅ Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")

    // 🔥 OPTIONAL (for your chat app - recommended)
    // implementation("com.google.firebase:firebase-auth")
    // implementation("com.google.firebase:firebase-firestore")
}