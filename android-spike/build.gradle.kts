// AGP 8.9.1 is the floor for compileSdk 36 (Android 16), which the target device runs.
// Android Studio may offer newer — accepting is fine, these are just a known-consistent
// starting pair.
plugins {
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}
