plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aadarsh.instakiller.spike"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aadarsh.instakiller.spike"
        // 29 = Android 10. Below this, background activity launch rules differ enough
        // that the spike would be testing a different problem than the one we have.
        minSdk = 29
        targetSdk = 35
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
