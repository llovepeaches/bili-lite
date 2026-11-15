// 工具链版本必须能读懂 backdrop 2.0.1 的 Gradle metadata：
// 它依赖 kotlin-stdlib 2.4.10 与 Compose Multiplatform 1.12.0
// （在 Android 上映射到 AndroidX Compose 1.12.1）。
// Kotlin 编译器低于库所用版本会报 "class file was compiled with a newer Kotlin"；
// Compose 1.12.1 的 AAR metadata 明确要求 compileSdk >= 37 且 AGP >= 9.1.0。
plugins {
    id("com.android.application") version "9.5.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10" apply false
}
