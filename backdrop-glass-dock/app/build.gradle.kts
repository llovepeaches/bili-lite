plugins {
    id("com.android.application")
    // AGP 9 起内置 Kotlin 支持（android.builtInKotlin=true），不再声明
    // org.jetbrains.kotlin.android —— 声明它会被 version-check 直接拒绝。
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.glassdock"
    // Compose 1.12.1（backdrop 2.0.1 经 CMP 1.12.0 映射）的 AAR metadata
    // 要求 compileSdk >= 37；AGP 需 >= 9.1.0。lens 本身只要求运行设备 API 33+。
    compileSdk = 37

    defaultConfig {
        applicationId = "com.example.glassdock"
        // 三档降级覆盖到 <31，因此 minSdk 可以低到 23；
        // FLAT 档在该区间完全不调用 drawBackdrop，零离屏缓冲。
        minSdk = 23
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))

    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // 现行正式库（Maven Central），不是 JitPack 的 com.github.Kyant0:AndroidLiquidGlass。
    // Gradle 会自动解析 android variant → backdrop-android:2.0.1。
    implementation("io.github.kyant0:backdrop:2.0.1")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // JVM 单元测试：覆盖三档降级判定、感知亮度与 overlay 混合等纯逻辑。
    testImplementation("junit:junit:4.13.2")
}
