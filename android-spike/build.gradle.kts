// Conservative, known-consistent versions. Android Studio will almost certainly offer to
// upgrade both on first open — accept it. If you do, bump compileSdk/targetSdk in
// app/build.gradle.kts to 36 at the same time; compileSdk 36 needs AGP 8.9 or newer.
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}
