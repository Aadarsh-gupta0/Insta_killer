plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aadarsh.instakiller.spike"
    // Android 16. Target device is a OnePlus 12R on OxygenOS 16.
    compileSdk = 36

    defaultConfig {
        applicationId = "com.aadarsh.instakiller.spike"
        // 29 = Android 10. Below this, background activity launch rules differ enough
        // that the spike would be testing a different problem than the one we have.
        minSdk = 29
        // Targeting 36 rather than staying low on purpose: the restrictions that come
        // with it (predictive back, edge-to-edge) are exactly what the real app will face,
        // and discovering them now is the point of a spike. See GateActivity's back
        // interception for the first one this broke.
        targetSdk = 36
        versionCode = 1
        versionName = "0.1-p0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// Deliberately empty. No AndroidX, no Compose, no Material — the spike uses framework
// APIs only, so nothing here can fail to resolve and nothing needs pinning in
// DECISIONS.md. The real app is Flutter anyway; this project is throwaway.
dependencies {
}
